import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:asn1lib/asn1lib.dart';
import 'package:pointycastle/export.dart';

class RsaCrypto {
  static AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> generateKeyPair() {
    final keyGen = RSAKeyGenerator();
    final secureRandom = _getSecureRandom();
    final keyParams = RSAKeyGeneratorParameters(
      BigInt.parse('65537'),
      2048,
      64,
    );
    keyGen.init(ParametersWithRandom(keyParams, secureRandom));
    final pair = keyGen.generateKeyPair();
    return AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>(
      pair.publicKey as RSAPublicKey,
      pair.privateKey as RSAPrivateKey,
    );
  }

  static SecureRandom _getSecureRandom() {
    final secureRandom = FortunaRandom();
    final seedSource = Random.secure();
    final seeds = <int>[];
    for (int i = 0; i < 32; i++) {
      seeds.add(seedSource.nextInt(256));
    }
    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));
    return secureRandom;
  }

  static String publicKeyToPem(RSAPublicKey key) {
    final algorithmSeq = ASN1Sequence();
    algorithmSeq.add(ASN1ObjectIdentifier.fromComponentString('1.2.840.113549.1.1.1'));
    algorithmSeq.add(ASN1Null());

    final publicKeySeq = ASN1Sequence();
    publicKeySeq.add(ASN1Integer(key.modulus!));
    publicKeySeq.add(ASN1Integer(key.exponent!));

    final bitString = ASN1BitString(publicKeySeq.encodedBytes);

    final outerSeq = ASN1Sequence();
    outerSeq.add(algorithmSeq);
    outerSeq.add(bitString);

    return _formatPem(base64Encode(outerSeq.encodedBytes), 'PUBLIC KEY');
  }

  static String privateKeyToPem(RSAPrivateKey key) {
    final pkcs1Seq = ASN1Sequence();
    pkcs1Seq.add(ASN1Integer(BigInt.zero));
    pkcs1Seq.add(ASN1Integer(key.modulus!));
    pkcs1Seq.add(ASN1Integer(key.exponent!));
    pkcs1Seq.add(ASN1Integer(key.privateExponent!));
    pkcs1Seq.add(ASN1Integer(key.p!));
    pkcs1Seq.add(ASN1Integer(key.q!));

    final outerSeq = ASN1Sequence();
    outerSeq.add(ASN1Integer(BigInt.zero));
    final algorithmSeq = ASN1Sequence();
    algorithmSeq.add(ASN1ObjectIdentifier.fromComponentString('1.2.840.113549.1.1.1'));
    algorithmSeq.add(ASN1Null());
    outerSeq.add(algorithmSeq);
    outerSeq.add(ASN1OctetString(pkcs1Seq.encodedBytes));

    return _formatPem(base64Encode(outerSeq.encodedBytes), 'PRIVATE KEY');
  }

  static String _formatPem(String base64, String label) {
    final buffer = StringBuffer();
    buffer.writeln('-----BEGIN $label-----');
    for (int i = 0; i < base64.length; i += 64) {
      final end = i + 64 > base64.length ? base64.length : i + 64;
      buffer.writeln(base64.substring(i, end));
    }
    buffer.writeln('-----END $label-----');
    return buffer.toString();
  }

  static RSAPublicKey publicKeyFromPem(String pem) {
    final der = _pemToDer(pem);
    final parser = ASN1Parser(der);
    final topSeq = parser.nextObject() as ASN1Sequence;

    final bitString = topSeq.elements[1] as ASN1BitString;
    final keyParser = ASN1Parser(Uint8List.fromList(bitString.contentBytes()));
    final keySeq = keyParser.nextObject() as ASN1Sequence;

    final modulus = (keySeq.elements[0] as ASN1Integer).valueAsBigInteger;
    final exponent = (keySeq.elements[1] as ASN1Integer).valueAsBigInteger;

    return RSAPublicKey(modulus, exponent);
  }

  static RSAPrivateKey privateKeyFromPem(String pem) {
    final der = _pemToDer(pem);
    final parser = ASN1Parser(der);
    final topSeq = parser.nextObject() as ASN1Sequence;

    final version = (topSeq.elements[0] as ASN1Integer).valueAsBigInteger;
    if (version != BigInt.zero) {
      throw ArgumentError('Unsupported PKCS#8 version: $version');
    }

    final octetString = topSeq.elements[2] as ASN1OctetString;
    final pkcs1Parser = ASN1Parser(Uint8List.fromList(octetString.contentBytes()));
    final pkcs1Seq = pkcs1Parser.nextObject() as ASN1Sequence;

    final modulus = (pkcs1Seq.elements[1] as ASN1Integer).valueAsBigInteger;
    final privateExponent = (pkcs1Seq.elements[3] as ASN1Integer).valueAsBigInteger;
    final p = (pkcs1Seq.elements[4] as ASN1Integer).valueAsBigInteger;
    final q = (pkcs1Seq.elements[5] as ASN1Integer).valueAsBigInteger;

    return RSAPrivateKey(modulus, privateExponent, p, q);
  }

  static Uint8List _pemToDer(String pem) {
    final clean = pem
        .replaceAll(RegExp(r'-----BEGIN [A-Z ]+-----'), '')
        .replaceAll(RegExp(r'-----END [A-Z ]+-----'), '')
        .replaceAll(RegExp(r'\s'), '');
    return base64Decode(clean);
  }

  static Uint8List encryptWithPublicKey(Uint8List data, RSAPublicKey publicKey) {
    final encryptor = OAEPEncoding(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));
    return _processBlocks(encryptor, data);
  }

  static Uint8List decryptWithPrivateKey(Uint8List data, RSAPrivateKey privateKey) {
    final decryptor = OAEPEncoding(RSAEngine())
      ..init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    return _processBlocks(decryptor, data);  // FIX: 原来是 privateKey，已修正为 data
  }

  static Uint8List _processBlocks(AsymmetricBlockCipher cipher, Uint8List data) {
    var input = data;
    var output = Uint8List(0);
    while (input.isNotEmpty) {
      final chunkSize = cipher.inputBlockSize;
      final chunk = input.length > chunkSize ? input.sublist(0, chunkSize) : input;
      input = input.length > chunkSize ? input.sublist(chunkSize) : Uint8List(0);
      final result = cipher.process(chunk);
      final newOutput = Uint8List(output.length + result.length);
      newOutput.setRange(0, output.length, output);
      newOutput.setRange(output.length, newOutput.length, result);
      output = newOutput;
    }
    return output;
  }

  static Uint8List encryptAesKeyForUser(Uint8List aesKey, String publicKeyPem) {
    final publicKey = publicKeyFromPem(publicKeyPem);
    return encryptWithPublicKey(aesKey, publicKey);
  }

  static Uint8List decryptAesKeyForUser(
      Uint8List encryptedAesKey, RSAPrivateKey privateKey) {
    return decryptWithPrivateKey(encryptedAesKey, privateKey);
  }
}