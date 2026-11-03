import 'dart:convert';
import 'package:cryptography/cryptography.dart';

/// Portable password encryption for exported backups only, not local database.
class BackupCrypto {
  static const iterations=210000;
  final cipher=AesGcm.with256bits();
  Future<SecretKey> _key(String password,List<int> salt) => Pbkdf2(macAlgorithm:Hmac.sha256(),iterations:iterations,bits:256).deriveKey(secretKey:SecretKey(utf8.encode(password)),nonce:salt);
  Future<List<int>> encrypt(List<int> zip,String password) async {
    if(password.length<12)throw StateError('Use a backup password of at least 12 characters.');
    final salt=await SecretKeyData.random(length:16).extractBytes();
    final box=await cipher.encrypt(zip,secretKey:await _key(password,salt),aad:utf8.encode('RowSkan backup v1'));
    return utf8.encode(jsonEncode({'format':'rowskan-encrypted','version':1,'kdf':'PBKDF2-HMAC-SHA256','iterations':iterations,'salt':base64Encode(salt),'nonce':base64Encode(box.nonce),'mac':base64Encode(box.mac.bytes),'ciphertext':base64Encode(box.cipherText)}));
  }
  bool isEncrypted(List<int> bytes)=>bytes.isNotEmpty&&bytes.first==123;
  Future<List<int>> decrypt(List<int> bytes,String password) async {
    if(bytes.length>310*1024*1024)throw StateError('Backup is too large.');
    final data=jsonDecode(utf8.decode(bytes));
    if(data is! Map||data['format']!='rowskan-encrypted'||data['version']!=1||data['iterations']!=iterations||data['kdf']!='PBKDF2-HMAC-SHA256')throw StateError('Unsupported encrypted backup.');
    final salt=base64Decode(data['salt'] as String),nonce=base64Decode(data['nonce'] as String),mac=base64Decode(data['mac'] as String);
    if(salt.length!=16||nonce.length!=12||mac.length!=16)throw StateError('Invalid encrypted backup.');
    try{return await cipher.decrypt(SecretBox(base64Decode(data['ciphertext'] as String),nonce:nonce,mac:Mac(mac)),secretKey:await _key(password,salt),aad:utf8.encode('RowSkan backup v1'));}
    on SecretBoxAuthenticationError {throw StateError('Wrong password or damaged backup. Inventory was not changed.');}
  }
}
