import '../../fetcher/client.dart';
import '../base_model.dart';

class UserRegisterRequest extends DynamicSchema<UserRegisterRequest> {
  UserRegisterRequest(super.data);

  String get firstName => getString('first_name')!;
  set firstName(String value) => setString('first_name', value);

  String get lastName => getString('last_name')!;
  set lastName(String value) => setString('last_name', value);

  String get email => getString('email')!;
  set email(String value) => setString('email', value);

  String get password => getString('password')!;
  set password(String value) => setString('password', value);
}

class LoginRequest extends DynamicSchema<LoginRequest> {
  LoginRequest(super.data);

  String get username => getString('username')!;
  set username(String value) => setString('username', value);

  String get password => getString('password')!;
  set password(String value) => setString('password', value);
}

class Token extends DynamicSchema<Token> {
  Token(Map<String, dynamic> data) : super({
    'token_type': 'bearer',
    ...data,
  });

  String get accessToken => getString('access_token')!;

  String get refreshToken => getString('refresh_token')!;

  String get tokenType => getString('token_type')!;
}

class TokenRefresh extends DynamicSchema<TokenRefresh> {
  TokenRefresh(super.data);

  String get refreshToken => getString('refresh_token')!;
  set refreshToken(String value) => setString('refresh_token', value);
}

/// Auth API
class AuthApi {
  final Fetcher _fetcher;

  final String? basePath;

  AuthApi(this._fetcher, {this.basePath});

  Future<SimpleMessage> register(UserRegisterRequest request) async {
    final response = await _fetcher.post('${basePath ?? ''}/auth/register', request.toJson());
    return SimpleMessage(response.data);
  }

  Future<Token> login(LoginRequest request) async {
    final response = await _fetcher.post('${basePath ?? ''}/auth/token', request.toJson());
    return Token(response.data);
  }

  Future<TokenRefresh> refresh(TokenRefresh request) async {
    final response = await _fetcher.post('${basePath ?? ''}/auth/refresh', request.toJson());
    return TokenRefresh(response.data);
  }
}
