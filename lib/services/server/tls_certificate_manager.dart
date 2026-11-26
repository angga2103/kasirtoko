import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';

import '../secret_vault.dart';

class TlsServerIdentity {
  final String certPem;
  final String privateKeyPem;
  final String sha256Hex;
  final String createdAt;
  final String expiresAt;
  final String? nextCertPem;
  final String? nextPrivateKeyPem;
  final String? nextSha256Hex;

  const TlsServerIdentity({
    required this.certPem,
    required this.privateKeyPem,
    required this.sha256Hex,
    required this.createdAt,
    required this.expiresAt,
    this.nextCertPem,
    this.nextPrivateKeyPem,
    this.nextSha256Hex,
  });

  String get shortPin =>
      sha256Hex.length >= 8 ? sha256Hex.substring(0, 8).toUpperCase() : sha256Hex.toUpperCase();

  SecurityContext toSecurityContext() {
    final ctx = SecurityContext(withTrustedRoots: false);
    ctx.useCertificateChainBytes(utf8.encode(certPem));
    ctx.usePrivateKeyBytes(utf8.encode(privateKeyPem));
    return ctx;
  }

  Map<String, dynamic> toJson() => {
        'cert_pem': certPem,
        'private_key_pem': privateKeyPem,
        'sha256_hex': sha256Hex,
        'created_at': createdAt,
        'expires_at': expiresAt,
        if (nextCertPem != null) 'next_cert_pem': nextCertPem,
        if (nextPrivateKeyPem != null) 'next_private_key_pem': nextPrivateKeyPem,
        if (nextSha256Hex != null) 'next_sha256_hex': nextSha256Hex,
      };

  factory TlsServerIdentity.fromJson(Map<String, dynamic> json) => TlsServerIdentity(
        certPem: (json['cert_pem'] ?? '').toString(),
        privateKeyPem: (json['private_key_pem'] ?? '').toString(),
        sha256Hex: (json['sha256_hex'] ?? '').toString(),
        createdAt: (json['created_at'] ?? '').toString(),
        expiresAt: (json['expires_at'] ?? '').toString(),
        nextCertPem: json['next_cert_pem']?.toString(),
        nextPrivateKeyPem: json['next_private_key_pem']?.toString(),
        nextSha256Hex: json['next_sha256_hex']?.toString(),
      );
}

class TlsCertificateManager {
  static const String _vaultKey = 'tls_server_identity_v1';
  final SecretVault Function() _vaultProvider;
  TlsServerIdentity? _cached;

  TlsCertificateManager({SecretVault Function()? vaultProvider})
      : _vaultProvider = vaultProvider ?? (() => SecretVault.instance);

  Future<TlsServerIdentity> getOrCreateIdentity({
    String commonName = 'KasirToko POS Server',
    List<String> extraIpAddresses = const [],
  }) async {
    if (_cached != null && !_isExpired(_cached!)) {
      return _cached!;
    }
    final storedRaw = await _vaultProvider().getRecord(_vaultKey);
    if (storedRaw != null && storedRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(storedRaw) as Map<String, dynamic>;
        final id = TlsServerIdentity.fromJson(decoded);
        if (id.certPem.isNotEmpty && id.privateKeyPem.isNotEmpty && !_isExpired(id)) {
          _cached = id;
          return id;
        }
      } catch (_) {}
    }

    final generated = await generateSelfSignedIdentity(
      commonName: commonName,
      extraIpAddresses: extraIpAddresses,
    );
    await _vaultProvider().putRecord(_vaultKey, jsonEncode(generated.toJson()));
    _cached = generated;
    return generated;
  }

  /// Prepares a staged `next` certificate so paired clients can learn `next_cert_sha256`
  /// via `/api/v1/security/cert-info` before cutover, preventing trust breakage during rotation.
  Future<TlsServerIdentity> stageRotation({
    String commonName = 'KasirToko POS Server',
    List<String> extraIpAddresses = const [],
  }) async {
    final current = await getOrCreateIdentity(
      commonName: commonName,
      extraIpAddresses: extraIpAddresses,
    );
    final next = await generateSelfSignedIdentity(
      commonName: commonName,
      extraIpAddresses: extraIpAddresses,
    );
    final updated = TlsServerIdentity(
      certPem: current.certPem,
      privateKeyPem: current.privateKeyPem,
      sha256Hex: current.sha256Hex,
      createdAt: current.createdAt,
      expiresAt: current.expiresAt,
      nextCertPem: next.certPem,
      nextPrivateKeyPem: next.privateKeyPem,
      nextSha256Hex: next.sha256Hex,
    );
    await _vaultProvider().putRecord(_vaultKey, jsonEncode(updated.toJson()));
    _cached = updated;
    return updated;
  }

  /// Promotes the staged `next` certificate (or creates a brand new identity immediately).
  Future<TlsServerIdentity> rotateNow({
    String commonName = 'KasirToko POS Server',
    List<String> extraIpAddresses = const [],
  }) async {
    final current = await getOrCreateIdentity(
      commonName: commonName,
      extraIpAddresses: extraIpAddresses,
    );
    late TlsServerIdentity promoted;
    if (current.nextCertPem != null &&
        current.nextPrivateKeyPem != null &&
        current.nextSha256Hex != null) {
      final now = DateTime.now().toUtc();
      promoted = TlsServerIdentity(
        certPem: current.nextCertPem!,
        privateKeyPem: current.nextPrivateKeyPem!,
        sha256Hex: current.nextSha256Hex!,
        createdAt: now.toIso8601String(),
        expiresAt: now.add(const Duration(days: 825)).toIso8601String(),
      );
    } else {
      promoted = await generateSelfSignedIdentity(
        commonName: commonName,
        extraIpAddresses: extraIpAddresses,
      );
    }
    await _vaultProvider().putRecord(_vaultKey, jsonEncode(promoted.toJson()));
    _cached = promoted;
    return promoted;
  }

  bool _isExpired(TlsServerIdentity id) {
    final exp = DateTime.tryParse(id.expiresAt);
    if (exp == null) return true;
    return DateTime.now().toUtc().isAfter(exp.subtract(const Duration(days: 7)));
  }

  static Future<TlsServerIdentity> generateSelfSignedIdentity({
    String commonName = 'KasirToko POS Server',
    List<String> extraIpAddresses = const [],
    int rsaBitLength = 2048,
  }) {
    final ips = <String>{'127.0.0.1', ...extraIpAddresses.where((e) => e.trim().isNotEmpty)}.toList();
    return Isolate.run(() => _generateSync(commonName, ips, rsaBitLength));
  }

  static TlsServerIdentity _generateSync(
    String commonName,
    List<String> ipv4List,
    int rsaBitLength,
  ) {
    final fortuna = FortunaRandom();
    final rng = Random.secure();
    final seed = Uint8List.fromList(List<int>.generate(32, (_) => rng.nextInt(256)));
    fortuna.seed(KeyParameter(seed));

    final keyGen = RSAKeyGenerator()
      ..init(
        ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.from(65537), rsaBitLength, 64),
          fortuna,
        ),
      );
    final pair = keyGen.generateKeyPair();
    final priv = pair.privateKey;
    final pub = pair.publicKey;

    final now = DateTime.now().toUtc();
    final notBefore = now.subtract(const Duration(minutes: 5));
    final notAfter = now.add(const Duration(days: 825));

    final serialBytes = List<int>.generate(16, (_) => rng.nextInt(256));
    serialBytes[0] &= 0x7F; // positive ASN.1 INTEGER
    if (serialBytes[0] == 0) serialBytes[0] = 0x01;
    var serial = BigInt.zero;
    for (final b in serialBytes) {
      serial = (serial << 8) | BigInt.from(b);
    }

    // 1. SubjectPublicKeyInfo
    final rsaPubSeq = ASN1Sequence(elements: [
      ASN1Integer(pub.modulus),
      ASN1Integer(pub.exponent),
    ]);
    final rsaOid = ASN1ObjectIdentifier([1, 2, 840, 113549, 1, 1, 1]);
    final rsaAlgId = ASN1Sequence(elements: [rsaOid, ASN1Null()]);
    final spki = ASN1Sequence(elements: [
      rsaAlgId,
      ASN1BitString(stringValues: rsaPubSeq.encode()),
    ]);

    // 2. Signature Algorithm: sha256WithRSAEncryption (1.2.840.113549.1.1.11)
    final sha256RsaOid = ASN1ObjectIdentifier([1, 2, 840, 113549, 1, 1, 11]);
    final sigAlgId = ASN1Sequence(elements: [sha256RsaOid, ASN1Null()]);

    // 3. Issuer & Subject Name
    final name = ASN1Sequence(elements: [
      ASN1Set(elements: [
        ASN1Sequence(elements: [
          ASN1ObjectIdentifier([2, 5, 4, 10]), // O
          ASN1UTF8String(utf8StringValue: 'KasirToko'),
        ]),
      ]),
      ASN1Set(elements: [
        ASN1Sequence(elements: [
          ASN1ObjectIdentifier([2, 5, 4, 3]), // CN
          ASN1UTF8String(utf8StringValue: commonName),
        ]),
      ]),
    ]);

    // 4. Extensions ([3] EXPLICIT SEQUENCE OF Extension)
    final sanElements = <ASN1Object>[
      ASN1IA5String(stringValue: 'localhost', tag: 0x82),
      ASN1IA5String(stringValue: 'kasirtoko.local', tag: 0x82),
    ];
    for (final ip in ipv4List) {
      final parsed = InternetAddress.tryParse(ip);
      if (parsed != null && parsed.rawAddress.length == 4) {
        sanElements.add(ASN1OctetString(octets: parsed.rawAddress, tag: 0x87));
      }
    }

    final extensions = ASN1Sequence(elements: [
      // BasicConstraints (cA = false)
      ASN1Sequence(elements: [
        ASN1ObjectIdentifier([2, 5, 29, 19]),
        ASN1Boolean(true),
        ASN1OctetString(octets: ASN1Sequence(elements: [ASN1Boolean(false)]).encode()),
      ]),
      // ExtendedKeyUsage (id-kp-serverAuth)
      ASN1Sequence(elements: [
        ASN1ObjectIdentifier([2, 5, 29, 37]),
        ASN1OctetString(
          octets: ASN1Sequence(elements: [
            ASN1ObjectIdentifier([1, 3, 6, 1, 5, 5, 7, 3, 1]),
          ]).encode(),
        ),
      ]),
      // SubjectAltName
      ASN1Sequence(elements: [
        ASN1ObjectIdentifier([2, 5, 29, 17]),
        ASN1OctetString(octets: ASN1Sequence(elements: sanElements).encode()),
      ]),
    ]);

    final tbs = ASN1Sequence(elements: [
      ASN1Sequence(tag: 0xA0, elements: [ASN1Integer(BigInt.from(2))]), // v3
      ASN1Integer(serial),
      sigAlgId,
      name,
      ASN1Sequence(elements: [ASN1UtcTime(notBefore), ASN1UtcTime(notAfter)]),
      name,
      spki,
      ASN1Sequence(tag: 0xA3, elements: [extensions]),
    ]);

    final tbsBytes = tbs.encode();

    // Sign TBSCertificate with SHA256withRSA
    final signer = RSASigner(SHA256Digest(), '0609608648016503040201');
    signer.init(true, PrivateKeyParameter<RSAPrivateKey>(priv));
    final sig = signer.generateSignature(tbsBytes);

    final cert = ASN1Sequence(elements: [
      tbs,
      sigAlgId,
      ASN1BitString(stringValues: sig.bytes),
    ]);
    final certDer = cert.encode();
    final fingerprintHex = sha256.convert(certDer).toString().toLowerCase();

    // PKCS#1 -> PKCS#8 PrivateKeyInfo PEM
    final p = priv.p!;
    final q = priv.q!;
    final d = priv.privateExponent!;
    final dP = d % (p - BigInt.one);
    final dQ = d % (q - BigInt.one);
    final qInv = q.modInverse(p);
    final pkcs1 = ASN1Sequence(elements: [
      ASN1Integer(BigInt.zero),
      ASN1Integer(priv.modulus),
      ASN1Integer(priv.publicExponent),
      ASN1Integer(d),
      ASN1Integer(p),
      ASN1Integer(q),
      ASN1Integer(dP),
      ASN1Integer(dQ),
      ASN1Integer(qInv),
    ]).encode();

    final pkcs8 = ASN1Sequence(elements: [
      ASN1Integer(BigInt.zero),
      rsaAlgId,
      ASN1OctetString(octets: pkcs1),
    ]).encode();

    return TlsServerIdentity(
      certPem: _encodePem('CERTIFICATE', certDer),
      privateKeyPem: _encodePem('PRIVATE KEY', pkcs8),
      sha256Hex: fingerprintHex,
      createdAt: now.toIso8601String(),
      expiresAt: notAfter.toIso8601String(),
    );
  }

  static String _encodePem(String label, Uint8List derBytes) {
    final b64 = base64.encode(derBytes);
    final buf = StringBuffer('-----BEGIN $label-----\n');
    for (int i = 0; i < b64.length; i += 64) {
      final end = (i + 64 < b64.length) ? i + 64 : b64.length;
      buf.writeln(b64.substring(i, end));
    }
    buf.write('-----END $label-----');
    return buf.toString();
  }
}
