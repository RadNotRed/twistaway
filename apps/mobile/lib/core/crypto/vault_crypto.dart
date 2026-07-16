import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class EncryptedPayload {
  const EncryptedPayload({
    required this.version,
    required this.algorithm,
    required this.nonce,
    required this.ciphertext,
    required this.tag,
    required this.keyDerivation,
    this.aad,
  });

  final int version;
  final String algorithm;
  final String nonce;
  final String ciphertext;
  final String tag;
  final String keyDerivation;
  final String? aad;

  Map<String, Object?> toJson() => {
        'version': version,
        'algorithm': algorithm,
        'nonce': nonce,
        'ciphertext': ciphertext,
        'tag': tag,
        'aad': aad,
        'keyDerivation': keyDerivation,
      };
}

class VaultCrypto {
  VaultCrypto({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _installSecretKey = 'twistaway.install_secret.v1';
  static final _random = Random.secure();

  final FlutterSecureStorage _secureStorage;
  final _aes = AesGcm.with256bits();

  Future<SecretKey> deriveVaultKey({
    required String password,
    required String userKdfSaltBase64,
  }) async {
    final installSecret = await _readOrCreateInstallSecret();
    final passwordKey = await Argon2id(
      memory: 65536,
      parallelism: 1,
      iterations: 3,
      hashLength: 32,
    ).deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: base64.decode(userKdfSaltBase64),
    );

    return Hkdf(
      hmac: Hmac.sha256(),
      outputLength: 32,
    ).deriveKey(
      secretKey: passwordKey,
      nonce: installSecret,
      info: utf8.encode('twistaway-user-vault-v1'),
    );
  }

  Future<EncryptedPayload> encryptJson({
    required SecretKey vaultKey,
    required Object value,
    String aad = 'twistaway-mobile-v1',
  }) async {
    final nonce =
        Uint8List.fromList(List<int>.generate(12, (_) => _random.nextInt(256)));
    final box = await _aes.encrypt(
      utf8.encode(jsonEncode(value)),
      secretKey: vaultKey,
      nonce: nonce,
      aad: utf8.encode(aad),
    );

    return EncryptedPayload(
      version: 1,
      algorithm: 'AES-256-GCM',
      nonce: base64Url.encode(box.nonce),
      ciphertext: base64Url.encode(box.cipherText),
      tag: base64Url.encode(box.mac.bytes),
      aad: base64Url.encode(utf8.encode(aad)),
      keyDerivation: 'argon2id-hkdf-sha256',
    );
  }

  Future<Map<String, Object?>> decryptJson({
    required SecretKey vaultKey,
    required EncryptedPayload payload,
  }) async {
    final clear = await _aes.decrypt(
      SecretBox(
        base64Url.decode(payload.ciphertext),
        nonce: base64Url.decode(payload.nonce),
        mac: Mac(base64Url.decode(payload.tag)),
      ),
      secretKey: vaultKey,
      aad: payload.aad == null ? const [] : base64Url.decode(payload.aad!),
    );

    return jsonDecode(utf8.decode(clear)) as Map<String, Object?>;
  }

  Future<List<int>> _readOrCreateInstallSecret() async {
    final existing = await _secureStorage.read(key: _installSecretKey);
    if (existing != null) {
      return base64.decode(existing);
    }

    final secret =
        Uint8List.fromList(List<int>.generate(32, (_) => _random.nextInt(256)));
    await _secureStorage.write(
        key: _installSecretKey, value: base64.encode(secret));
    return secret;
  }
}
