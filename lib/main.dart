// Entrypoint por defecto. Para builds reales usar --target lib/main_staging.dart
// o lib/main_production.dart (un flavor por entorno).
import 'main_staging.dart' as staging;
void main() => staging.main();
