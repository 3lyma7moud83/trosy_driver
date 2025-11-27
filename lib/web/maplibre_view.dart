import 'dart:html' as html;
import 'dart:ui_web' as ui;

void registerMapLibreView() {
  ui.platformViewRegistry.registerViewFactory(
    'maplibre-view',
    (int viewId) {
      final div = html.DivElement()
        ..id = 'mapLibreContainer'
        ..style.width = '100%'
        ..style.height = '100%';

      return div;
    },
  );
}
