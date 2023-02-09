import 'package:envied/envied.dart';

part 'env.g.dart';

@Envied(path: '.env')
abstract class Env {
  @EnviedField(varName: 'TMDBKEY')
  static const tmdbApiKey = _Env.tmdbApiKey;

}
