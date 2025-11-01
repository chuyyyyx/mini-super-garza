import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart' as pwlib;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:http/http.dart' as http;
import 'package:csv/csv.dart';

void main() => runApp(const GarzaApp());

class GarzaApp extends StatelessWidget {
  const GarzaApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mini Súper Garza',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2E7D32),
        brightness: Brightness.light,
      ),
      home: const Shell(),
    );
  }
}

// ===================== MODELOS =====================
class Producto {
  final String id;
  bool fav;
  String nombre;
  String sku;
  String presentacion;
  double precioCompra;
  double precioVenta;
  int stock;
  double alertaMin;
  bool visible;
  String? imageUrl;     // URL remota
  String? imageBase64;  // Imagen local (cámara/galería) guardada en base64
  bool esGranel;        // a granel o unitario

  Producto({
    required this.id,
    this.fav = false,
    required this.nombre,
    required this.sku,
    this.presentacion = '',
    this.precioCompra = 0,
    this.precioVenta = 0,
    this.stock = 0,
    this.alertaMin = 0,
    this.visible = true,
    this.imageUrl,
    this.imageBase64,
    this.esGranel = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'fav': fav,
        'nombre': nombre,
        'sku': sku,
        'presentacion': presentacion,
        'precioCompra': precioCompra,
        'precioVenta': precioVenta,
        'stock': stock,
        'alertaMin': alertaMin,
        'visible': visible,
        'imageUrl': imageUrl,
        'imageBase64': imageBase64,
        'esGranel': esGranel,
      };

  static Producto fromJson(Map<String, dynamic> m) => Producto(
        id: m['id'] as String,
        fav: (m['fav'] ?? false) as bool,
        nombre: (m['nombre'] ?? '') as String,
        sku: (m['sku'] ?? '') as String,
        presentacion: (m['presentacion'] ?? '') as String,
        precioCompra: (m['precioCompra'] ?? 0).toDouble(),
        precioVenta: (m['precioVenta'] ?? 0).toDouble(),
        stock: (m['stock'] ?? 0).toInt(),
        alertaMin: (m['alertaMin'] ?? 0).toDouble(),
        visible: (m['visible'] ?? true) as bool,
        imageUrl: m['imageUrl'] as String?,
        imageBase64: m['imageBase64'] as String?,
        esGranel: (m['esGranel'] ?? false) as bool,
      );
}

class LineaVenta {
  final Producto producto;
  double cantidad;
  LineaVenta({required this.producto, this.cantidad = 1});
  double get subtotal => cantidad * producto.precioVenta;
  Map<String, dynamic> toJson() => {
        'productoId': producto.id,
        'nombre': producto.nombre,
        'sku': producto.sku,
        'ppu': producto.precioVenta,
        'cantidad': cantidad,
        'subtotal': subtotal,
      };
}

class Venta {
  final String id;
  final DateTime fecha;
  final List<LineaVenta> lineas;
  final double total;
  final double efectivo;
  final double cambio;
  final String? corteId; // nuevo: vínculo al corte

  Venta({
    required this.id,
    required this.fecha,
    required this.lineas,
    required this.total,
    required this.efectivo,
    required this.cambio,
    this.corteId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'fecha': fecha.toIso8601String(),
        'total': total,
        'efectivo': efectivo,
        'cambio': cambio,
        'corteId': corteId,
        'lineas': lineas.map((e) => e.toJson()).toList(),
      };

  static Venta fromJson(Map<String, dynamic> m) => Venta(
        id: m['id'] as String,
        fecha: DateTime.parse(m['fecha'] as String),
        total: (m['total'] as num).toDouble(),
        efectivo: (m['efectivo'] as num).toDouble(),
        cambio: (m['cambio'] as num).toDouble(),
        corteId: m['corteId'] as String?,
        lineas: (m['lineas'] as List)
            .map((e) => LineaVenta(
                  producto: Producto(
                    id: e['productoId'],
                    nombre: e['nombre'],
                    sku: e['sku'],
                  ),
                  cantidad: (e['cantidad'] as num).toDouble(),
                ))
            .toList(),
      );
}

// Corte de caja
class Corte {
  final String id; // ej: "c_2025-10-27_1"
  final DateTime inicio;
  DateTime? fin;
  String? notas;
  Corte({required this.id, required this.inicio, this.fin, this.notas});
  bool get abierto => fin == null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'inicio': inicio.toIso8601String(),
        'fin': fin?.toIso8601String(),
        'notas': notas,
      };

  static Corte fromJson(Map<String, dynamic> m) => Corte(
        id: m['id'] as String,
        inicio: DateTime.parse(m['inicio'] as String),
        fin: m['fin'] == null ? null : DateTime.parse(m['fin'] as String),
        notas: m['notas'] as String?,
      );
}

class MovimientoInv {
  final String id;
  final DateTime fecha;
  final String productoId;
  final String nombreProducto;
  final double cantidad;   // positivo = entrada, negativo = salida
  final double antes;      // stock antes del movimiento
  final double despues;    // stock después del movimiento
  final String tipo;       // 'venta' | 'entrada' | 'salida' | 'ajuste+/-'
  final String? motivo;    // opcional
  final String? refVentaId;

  MovimientoInv({
    required this.id,
    required this.fecha,
    required this.productoId,
    required this.nombreProducto,
    required this.cantidad,
    required this.antes,
    required this.despues,
    required this.tipo,
    this.motivo,
    this.refVentaId,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'fecha': fecha.toIso8601String(),
    'productoId': productoId,
    'nombreProducto': nombreProducto,
    'cantidad': cantidad,
    'antes': antes,
    'despues': despues,
    'tipo': tipo,
    'motivo': motivo,
    'refVentaId': refVentaId,
  };

  static MovimientoInv fromJson(Map<String, dynamic> m) => MovimientoInv(
    id: m['id'],
    fecha: DateTime.parse(m['fecha']),
    productoId: m['productoId'],
    nombreProducto: m['nombreProducto'],
    cantidad: (m['cantidad'] as num).toDouble(),
    antes: (m['antes'] as num).toDouble(),
    despues: (m['despues'] as num).toDouble(),
    tipo: m['tipo'],
    motivo: m['motivo'],
    refVentaId: m['refVentaId'],
  );
}

// ===================== REPO =====================
class Repo extends ChangeNotifier {
  static const _kKeyProductos = 'productos_json_v3';
  static const _kKeyMovs = 'movs_json_v1';
  static const _kKeyVentas = 'ventas_json_v2'; // bump por corteId
  static const _kKeyCortes = 'cortes_json_v1';
  static const _kKeyCorteAbierto = 'corte_abierto_id';

  final List<Producto> _productos = [];
  final List<MovimientoInv> _movs = [];
  final List<Venta> _ventas = [];
  final List<Corte> _cortes = [];
  String? _corteAbiertoId;

  List<Producto> get productos => List.unmodifiable(_productos);
  List<MovimientoInv> get movimientos => List.unmodifiable(_movs);
  List<Venta> get ventas => List.unmodifiable(_ventas);
  List<Corte> get cortes => List.unmodifiable(_cortes);
  Corte? get corteAbierto {
    try { return _cortes.firstWhere((c) => c.id == _corteAbiertoId); } catch (_) { return null; }
  }

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final rawP = sp.getString(_kKeyProductos);
    if (rawP == null) {
      _productos.addAll(_seed());
      await saveProductos();
    } else {
      final List list = jsonDecode(rawP) as List;
      _productos
        ..clear()
        ..addAll(list.map((e) => Producto.fromJson(Map<String, dynamic>.from(e))));
    }

    final rawV = sp.getString(_kKeyVentas);
    if (rawV != null) {
      final List list = jsonDecode(rawV) as List;
      _ventas
        ..clear()
        ..addAll(list.map((e) => Venta.fromJson(Map<String, dynamic>.from(e))));
    }

    final rawC = sp.getString(_kKeyCortes);
    if (rawC != null) {
      final List list = jsonDecode(rawC) as List;
      _cortes
        ..clear()
        ..addAll(list.map((e) => Corte.fromJson(Map<String, dynamic>.from(e))));
    }
    _corteAbiertoId = sp.getString(_kKeyCorteAbierto);

    final rawM = sp.getString(_kKeyMovs);
    if (rawM != null) {
      final List list = jsonDecode(rawM) as List;
      _movs
        ..clear()
        ..addAll(list.map((e) => MovimientoInv.fromJson(Map<String, dynamic>.from(e))));
    }

    notifyListeners();
  }

  Future<void> saveProductos() async {
    final sp = await SharedPreferences.getInstance();
    final raw = jsonEncode(_productos.map((p) => p.toJson()).toList());
    await sp.setString(_kKeyProductos, raw);
  }

  Future<void> saveVentas() async {
    final sp = await SharedPreferences.getInstance();
    final raw = jsonEncode(_ventas.map((v) => v.toJson()).toList());
    await sp.setString(_kKeyVentas, raw);
  }

  Future<void> _saveCortes() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kKeyCortes, jsonEncode(_cortes.map((c) => c.toJson()).toList()));
    if (_corteAbiertoId == null) {
      await sp.remove(_kKeyCorteAbierto);
    } else {
      await sp.setString(_kKeyCorteAbierto, _corteAbiertoId!);
    }
  }

  Future<void> _saveMovs() async {
  final sp = await SharedPreferences.getInstance();
  final raw = jsonEncode(_movs.map((m) => m.toJson()).toList());
  await sp.setString(_kKeyMovs, raw);
  }

  void _logMovimiento({
  required Producto prod,
  required double delta,   // +entrada, -salida
  required String tipo,    // 'venta' | 'entrada' | 'salida' | 'ajuste+' | 'ajuste-'
  String? motivo,
  String? refVentaId,
  DateTime? fecha,
  double? antesOverride,   // opcional si ya calculaste antes/after afuera
  double? despuesOverride,
}) {
  final ahora = fecha ?? DateTime.now();
  final antes = antesOverride ?? prod.stock.toDouble();
  final despues = despuesOverride ?? (antes + delta);

  _movs.insert(0, MovimientoInv(
    id: 'mov_${ahora.microsecondsSinceEpoch}',
    fecha: ahora,
    productoId: prod.id,
    nombreProducto: prod.nombre,
    cantidad: delta,
    antes: antes,
    despues: despues,
    tipo: tipo,
    motivo: motivo,
    refVentaId: refVentaId,
  ));
}

  // CRUD Producto
  void addProducto(Producto p) { _productos.insert(0, p); saveProductos(); notifyListeners(); }
  void updateProducto(Producto p) { saveProductos(); notifyListeners(); }
  void toggleFavorito(Producto p) { p.fav = !p.fav; saveProductos(); notifyListeners(); }
  void toggleVisible(Producto p) { p.visible = !p.visible; saveProductos(); notifyListeners(); }
  void removeProducto(Producto p) { _productos.removeWhere((x) => x.id == p.id); saveProductos(); notifyListeners(); }

  List<Producto> buscar(String q, {int tab = 0}) {
    Iterable<Producto> src = _productos.where((p) => p.visible);
    if (tab == 1) src = src.where((p) => p.fav);
    if (tab == 2) src = src.where((p) => p.esGranel); // pestaña granel usa flag
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return src.toList();
    return src.where((p) => p.nombre.toLowerCase().contains(s) || p.sku.toLowerCase().contains(s)).toList();
  }

  Producto? porSkuExacto(String code) {
    final q = code.trim().toLowerCase();
    try { return _productos.firstWhere((p) => p.sku.toLowerCase() == q && p.visible); }
    catch (_) { return null; }
  }

  // Ventas
  Future<void> registrarVenta(Venta v) async {
    // Asignar corte actual si existe
    final venta = (_corteAbiertoId == null) 
    ? v 
    : Venta(
      id: v.id,
      fecha: v.fecha,
      lineas: v.lineas,
      total: v.total,
      efectivo: v.efectivo,
      cambio: v.cambio,
      corteId: _corteAbiertoId,
    );

    _ventas.add(venta);
    // Descuento de inventario (controlando unitario vs granel)
    for (final l in venta.lineas) {
      final idx = _productos.indexWhere((p) => p.id == l.producto.id);
      if (idx == -1) continue; // no encontrado, no descuenta
      final prod = _productos[idx];

      final desc = prod.esGranel ? l.cantidad : l.cantidad.floorToDouble();
      final antes = prod.stock.toDouble();
      final despues = (antes - desc).clamp(0, double.infinity);

      prod.stock = despues.toInt();

      _logMovimiento(
        prod: prod,
        delta: -desc,
        tipo: 'venta',
        motivo: 'Venta ${venta.id}',
        refVentaId: venta.id,
        fecha: venta.fecha,
        antesOverride: antes,
        despuesOverride: despues.toDouble(),
      );
    }
    await _saveMovs(); 
    await saveVentas();
    await saveProductos();
    notifyListeners();
  }

  double totalDelDia(DateTime fecha) {
    final f0 = DateTime(fecha.year, fecha.month, fecha.day);
    final f1 = f0.add(const Duration(days: 1));
    return _ventas
        .where((v) => v.fecha.isAfter(f0.subtract(const Duration(microseconds: 1))) && v.fecha.isBefore(f1))
        .fold(0.0, (a, v) => a + v.total);
  }

  // Cortes API
  Future<Corte> abrirCorte({String? notas}) async {
    if (corteAbierto != null) return corteAbierto!; // ya hay uno
    final hoy = DateTime.now();
    final serialDelDia = 1 + _cortes.where((c) =>
      c.inicio.year == hoy.year && c.inicio.month == hoy.month && c.inicio.day == hoy.day
    ).length;
    final id = 'c_${hoy.toIso8601String().substring(0,10)}_$serialDelDia';
    final c = Corte(id: id, inicio: hoy, notas: notas);
    _cortes.insert(0, c);
    _corteAbiertoId = id;
    await _saveCortes();
    notifyListeners();
    return c;
  }

  Future<void> cerrarCorte({String? notas}) async {
    final c = corteAbierto;
    if (c == null) return;
    c.fin = DateTime.now();
    if (notas != null && notas.trim().isNotEmpty) c.notas = notas;
    _corteAbiertoId = null;
    await _saveCortes();
    notifyListeners();
  }

  List<Venta> ventasDeCorte(String corteId) =>
      _ventas.where((v) => v.corteId == corteId).toList();

  double totalDeCorte(String corteId) =>
      ventasDeCorte(corteId).fold(0.0, (a, v) => a + v.total);

  int itemsDeCorte(String corteId) =>
      ventasDeCorte(corteId).fold(0, (a, v) => a + v.lineas.fold<int>(0, (x, l) => x + l.cantidad.toInt()));

  List<Producto> _seed() => [
    Producto(id:'p1', nombre:'COCA-COLA 500 ML', sku:'7501005101234', presentacion:'500 ml', precioCompra:10, precioVenta:15, stock:25, alertaMin:5, esGranel:false),
    Producto(id:'p2', nombre:'GOLOS 40 GR S/T', sku:'GOLOS40', presentacion:'40 GR', precioCompra:6, precioVenta:10, stock:30, alertaMin:5, esGranel:false),
    Producto(id:'p3', nombre:'CACAHUATES BOKADS', sku:'BOKADS55', presentacion:'55 GR', precioCompra:9, precioVenta:12, stock:20, alertaMin:5, esGranel:false),
    Producto(id:'p4', nombre:'CIEL AGUA PURIFICADA', sku:'AGUACIEL600', presentacion:'600 ML', precioCompra:6, precioVenta:9, stock:33, alertaMin:5, fav:true, esGranel:false),
    Producto(id:'p5', nombre:'ARROZ', sku:'ARROZKG', presentacion:'A GRANEL', precioCompra:25, precioVenta:35, stock:20, alertaMin:5, esGranel:true),
  ];

  bool _parseBool(dynamic v) {
  final s = (v ?? '').toString().trim().toLowerCase();
  return s == 'true' || s == '1' || s == 'sí' || s == 'si' || s == 'yes';
  }

  double _parseDouble(dynamic v) => (v == null || v.toString().trim().isEmpty)
      ? 0.0
      : double.tryParse(v.toString().replaceAll(',', '.')) ?? 0.0;

  int _parseInt(dynamic v) => (v == null || v.toString().trim().isEmpty)
      ? 0
      : int.tryParse(v.toString().split('.').first) ?? 0;

  /// Sincroniza productos desde un CSV público de Google Sheets.
  /// Hace merge por SKU (si coincide, actualiza; si no, crea).
  Future<(int actualizados, int nuevos)> syncProductosDesdeCsv(String csvUrl) async {
    final resp = await http.get(Uri.parse(csvUrl));
    if (resp.statusCode != 200) {
      throw Exception('No se pudo descargar el CSV (${resp.statusCode})');
    }

    final rows = const CsvToListConverter(
      eol: '\n',
      fieldDelimiter: ',',
      shouldParseNumbers: false,
    ).convert(resp.body);

    if (rows.isEmpty) return (0, 0);

    // Mapear encabezados
    final headers = rows.first.map((e) => e.toString().trim()).toList();
    int idx(String name) => headers.indexWhere((h) => h.toLowerCase() == name.toLowerCase());

    final iId            = idx('id');
    final iNombre        = idx('nombre');
    final iSku           = idx('sku');
    final iPresentacion  = idx('presentacion');
    final iPrecioCompra  = idx('precioCompra');
    final iPrecioVenta   = idx('precioVenta');
    final iStock         = idx('stock');
    final iAlertaMin     = idx('alertaMin');
    final iVisible       = idx('visible');
    final iImageUrl      = idx('imageUrl');
    final iEsGranel      = idx('esGranel');

    int updated = 0, created = 0;

    for (var r = 1; r < rows.length; r++) {
      final row = rows[r];
      String getS(int i) => (i >= 0 && i < row.length) ? (row[i]?.toString() ?? '').trim() : '';

      final id           = getS(iId).isNotEmpty ? getS(iId) : 'p_${DateTime.now().microsecondsSinceEpoch}';
      final nombre       = getS(iNombre);
      final sku          = getS(iSku);
      final present      = getS(iPresentacion);
      final pc           = _parseDouble(iPrecioCompra >= 0 ? row[iPrecioCompra] : null);
      final pv           = _parseDouble(iPrecioVenta  >= 0 ? row[iPrecioVenta]  : null);
      final stk          = _parseInt(iStock >= 0 ? row[iStock] : null);
      final alerta       = _parseDouble(iAlertaMin >= 0 ? row[iAlertaMin] : null);
      final visible      = _parseBool(iVisible >= 0 ? row[iVisible] : null);
      final imageUrl     = getS(iImageUrl);
      final esGranel     = _parseBool(iEsGranel >= 0 ? row[iEsGranel] : null);

      // Mínimos requeridos
      if (nombre.isEmpty || sku.isEmpty) continue;

      // Merge por SKU
      final idxExistente = _productos.indexWhere((p) => p.sku.toLowerCase() == sku.toLowerCase());
      if (idxExistente >= 0) {
        final p = _productos[idxExistente];
        p.nombre        = nombre;
        p.presentacion  = present;
        p.precioCompra  = pc;
        p.precioVenta   = pv;
        p.stock         = stk;
        p.alertaMin     = alerta;
        p.visible       = visible;
        p.imageUrl      = imageUrl.isEmpty ? null : imageUrl;
        p.esGranel      = esGranel;
        updated++;
      } else {
        _productos.add(Producto(
          id: id,
          nombre: nombre,
          sku: sku,
          presentacion: present,
          precioCompra: pc,
          precioVenta: pv,
          stock: stk,
          alertaMin: alerta,
          visible: visible,
          imageUrl: imageUrl.isEmpty ? null : imageUrl,
          esGranel: esGranel,
        ));
        created++;
      }
    }

    await saveProductos();
    notifyListeners();
    return (updated, created);
  }
}





// ===================== SHELL =====================
class Shell extends StatefulWidget { const Shell({super.key}); @override State<Shell> createState() => _ShellState(); }
class _ShellState extends State<Shell> with TickerProviderStateMixin {
  int index = 0;
  final Repo repo = Repo();
  final TextEditingController searchCtrl = TextEditingController();
  late final TabController ventasTabs;
  final List<List<LineaVenta>> carritos = [[], [], []];
  bool _loaded = false;

  @override
  void initState() { super.initState(); ventasTabs = TabController(length: 3, vsync: this); repo.load().then((_) => setState(() => _loaded = true)); }
  @override void dispose() { ventasTabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: repo,
      builder: (_, __) => Scaffold(
        appBar: AppBar(title: _SearchBar(title: 'Mini Súper Garza', searchCtrl: searchCtrl, onMic: () => _snack('Búsqueda por voz (demo)'))),
        body: Row(children: [
          NavigationRail(
            selectedIndex: index, onDestinationSelected: (i) => setState(() => index = i), labelType: NavigationRailLabelType.all,
            leading: Padding(padding: const EdgeInsets.all(8.0), child: Text('Mini Súper Garza', textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w900))),
            destinations: const [
              NavigationRailDestination(icon: Icon(Icons.point_of_sale), label: Text('Ventas')),
              NavigationRailDestination(icon: Icon(Icons.admin_panel_settings), label: Text('Admin')),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: !_loaded ? const Center(child: CircularProgressIndicator()) : IndexedStack(index: index, children: [
              _VentasPage(
                repo: repo, ventasTabs: ventasTabs, carritos: carritos, searchCtrl: searchCtrl,
                onToggleFav: (p) => repo.toggleFavorito(p),
                onAdd: (p) => _addToCart(p),
                onEscanear: () => _snack('Escáner (demo)'),
                onCobrar: () => _abrirCobro(context),
                onVaciarCarrito: () => setState(() => carritos[ventasTabs.index].clear()),
              ),
              AdminHome(repo: repo),
            ]),
          ),
        ]),
      ),
    );
  }

  double _subtotal(List<LineaVenta> l) => l.fold(0.0, (a, e) => a + e.subtotal);

  void _abrirCobro(BuildContext context) async {
    final lineas = carritos[ventasTabs.index];
    if (lineas.isEmpty) { _snack('No hay productos en la venta'); return; }

    final excedidas = <Map<String, dynamic>>[];
    for (final l in lineas) {
      final p = repo.productos.firstWhere((x) => x.id == l.producto.id, orElse: () => l.producto);
      final disponible = p.stock.toDouble();
      final pedida = l.cantidad;
      if (pedida > disponible) {
        excedidas.add({
          'nombre': p.nombre,
          'pedida': pedida,
          'stock': disponible,
        });
      }
    }

    if (excedidas.isNotEmpty) {
        final seguir = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: const Text('Cantidades mayores al stock'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Se ajustarán a lo disponible:'),
                  const SizedBox(height: 8),
                  ...excedidas.map((e) => Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '• ${e['nombre']} — pedido: ${e['pedida']}  stock: ${e['stock']}',
                      maxLines: 2,
                    ),
                  )),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
              FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Ajustar y continuar')),
            ],
          ),
        );

    if (seguir != true) return;

    // Ajuste automático al stock real
    setState(() {
      for (final l in lineas) {
        final p = repo.productos.firstWhere((x) => x.id == l.producto.id, orElse: () => l.producto);
        final disponible = p.stock.toDouble();
        if (l.cantidad > disponible) {
          l.cantidad = p.esGranel ? disponible : disponible.floorToDouble();
        }
      }
    });
  }

    final total = _subtotal(lineas);
    final efectivo = await showDialog<double>(context: context, builder: (ctx) => _CobroDialog(total: total));
    if (efectivo == null) return;
    final cambio = (efectivo - total).clamp(0, 9999999).toDouble();

    final venta = Venta(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      fecha: DateTime.now(),
      lineas: List<LineaVenta>.from(lineas),
      total: total, efectivo: efectivo, cambio: cambio,
    );
    await repo.registrarVenta(venta);
    setState(() => lineas.clear());

    await _imprimirTicket(venta);
    _snack('Venta registrada. Cambio: \$${cambio.toStringAsFixed(2)}');
  }

// Helpers locales
String _money(double x) => '\$${x.toStringAsFixed(2)}';
pw.TextStyle get _h1 => pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold);
pw.TextStyle get _h2 => pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold);
pw.TextStyle get _small => const pw.TextStyle(fontSize: 9);
String _linea(String ch, [int n = 30]) => List.filled(n, ch).join();

// ===== Nueva impresión de ticket =====
Future<void> _imprimirTicket(Venta v) async {
  final doc = pw.Document();

  // Datos fijos del encabezado
  const nombreNegocio = 'Mini Súper Garza'; // cámbialo si quieres
  const direccion =
      'Carr. a la Cola de Caballo SN-C ESTANQUILLO EL ENCINO,\n'
      'Cieneguilla, 67308 Santiago, N.L.';
  const rfc = 'XAXX010101000'; // RFC genérico

  // Cantidad total de artículos (unitarios = enteros, granel = decimales)
  double itemsTotal = 0;
  for (final l in v.lineas) {
    itemsTotal += l.producto.esGranel ? l.cantidad : l.cantidad.floorToDouble();
  }
  String itemsFmt =
      (itemsTotal == itemsTotal.roundToDouble()) ? itemsTotal.toInt().toString()
                                                 : itemsTotal.toStringAsFixed(3);

  doc.addPage(
    pw.Page(
      pageFormat: pwlib.PdfPageFormat.roll80,
      margin: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      build: (pw.Context ctx) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // (Opcional) Logo: si tienes un base64 en `logoBase64`, puedes agregarlo aquí
            // if (logoBase64 != null && logoBase64!.isNotEmpty) ...[
            //   pw.Center(pw.Image(pw.MemoryImage(base64Decode(logoBase64!)), width: 48)),
            //   pw.SizedBox(height: 6),
            // ],

            // Nombre tienda
            pw.Center(child: pw.Text(nombreNegocio, style: _h1)),
            pw.SizedBox(height: 6),

            // Dirección y RFC, centrados
            pw.Center(child: pw.Text(direccion, style: _small, textAlign: pw.TextAlign.center)),
            pw.Center(child: pw.Text('RFC: $rfc', style: _small)),
            pw.SizedBox(height: 8),

            // Fecha centrada
            pw.Center(child: pw.Text(
              _fechaBonita(v.fecha),
              style: _small,
            )),
            pw.SizedBox(height: 8),

            // Folio alineado derecha
            pw.Row(
              children: [
                pw.Expanded(child: pw.SizedBox()),
                pw.Text('Folio:  ${v.id}', style: _small),
              ],
            ),
            pw.SizedBox(height: 6),

            // Encabezado tabla
            pw.Text(_linea('=')),
            pw.Row(
              children: [
                pw.SizedBox(width: 36, child: pw.Text('Cant.', style: _h2)),
                pw.Expanded(child: pw.Text('Descripcion', style: _h2)),
                pw.SizedBox(width: 64, child: pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text('Importe', style: _h2),
                )),
              ],
            ),
            pw.Text(_linea('=')),
            pw.SizedBox(height: 2),

            // Líneas de productos (sin PPU, como el ejemplo)
            ...v.lineas.map((l) {
              final cant = l.producto.esGranel
                  ? l.cantidad.toStringAsFixed(3)
                  : l.cantidad.toStringAsFixed(0);

              // Detectar unidad
              String unidad = l.producto.presentacion.trim();

              if (unidad.isEmpty) {
                final nombre = l.producto.nombre.toLowerCase();
                if (nombre.contains('kg') || nombre.contains('kilo')) unidad = 'kg';
                else if (nombre.contains(' gr') || nombre.endsWith('gr') || nombre.contains('gramo')) unidad = 'g';
                else if (nombre.contains(' lt') || nombre.contains('litro')) unidad = 'L';
                else if (nombre.contains(' ml') || nombre.endsWith('ml')) unidad = 'ml';
              }

              final nombreFinal = unidad.isNotEmpty
                  ? '${l.producto.nombre} $unidad'
                  : l.producto.nombre;

              final importe = _money(l.subtotal);
              
              return pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.SizedBox(width: 36, child: pw.Text(cant)),
                    pw.Expanded(child: pw.Text(nombreFinal, maxLines: 2)),
                    pw.SizedBox(
                      width: 64,
                      child: pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text(importe),
                      ),
                    ),
                  ],
                ),
              );
            }),

            pw.SizedBox(height: 6),
            pw.Text(_linea('=')),
            pw.SizedBox(height: 6),

            // Número de artículos
            pw.Row(
              children: [
                pw.Expanded(child: pw.Text('No. de Artículos:', style: _small)),
                pw.Text(itemsFmt, style: _small),
              ],
            ),
            pw.SizedBox(height: 8),

            // Totales (alineados derecha)
            _filaTotal('Total:', _money(v.total)),
            _filaTotal('Pago Con:', _money(v.efectivo)),
            _filaTotal('Su Cambio:', _money(v.cambio)),

            pw.SizedBox(height: 12),

            // Mensaje de despedida
            pw.Center(child: pw.Text('Gracias por su compra', style: _small)),
            pw.Center(child: pw.Text('vuelva pronto', style: _small)),
          ],
        );
      },
    ),
  );

  await Printing.layoutPdf(onLayout: (format) async => doc.save());
}

// ---- sub-helpers de layout para el ticket ----
pw.Widget _filaTotal(String etiqueta, String valor) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      children: [
        pw.Expanded(child: pw.Text(etiqueta, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold))),
        pw.Text(valor, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
      ],
    ),
  );
}

String _fechaBonita(DateTime f) {
  // 26/12/2016 07:51 pm
  final dd = f.day.toString().padLeft(2, '0');
  final mm = f.month.toString().padLeft(2, '0');
  final yyyy = f.year.toString();
  int hh = f.hour;
  final ampm = hh >= 12 ? 'pm' : 'am';
  hh = hh % 12; if (hh == 0) hh = 12;
  final min = f.minute.toString().padLeft(2, '0');
  return '$dd/$mm/$yyyy  ${hh.toString().padLeft(2, '0')}:$min $ampm';
}

  void _addToCart(Producto p) {
    if (p.stock <= 0) {
    _snack('Producto agotado: ${p.nombre}');
    return;
  }
    final cart = carritos[ventasTabs.index];
    final idx = cart.indexWhere((l) => l.producto.id == p.id);

    final max = p.esGranel
      ? p.stock.toDouble()
      : p.stock.floorToDouble();

    if (idx >= 0) 
    { 
      final l = cart[idx];
      double nueva = l.cantidad + 1;
      if (!p.esGranel) nueva = nueva.floorToDouble();
      if (nueva > max) nueva = max; // ← tope por stock real
      setState(() => l.cantidad = nueva);
    }
    else { 
      final inicial = p.esGranel ? 1.0 : 1.0;
      final cantidad = inicial > max ? max : inicial;
      setState(() => cart.add(LineaVenta(producto: p, cantidad: cantidad)));
      }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

// ===================== VENTAS UI =====================
class _SearchBar extends StatelessWidget {
  final String title; final TextEditingController searchCtrl; final VoidCallback onMic;
  const _SearchBar({required this.title, required this.searchCtrl, required this.onMic});
  @override Widget build(BuildContext context) {
    return Row(children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(width: 16),
      Expanded(child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(24)),
        child: Row(children: [
          const Icon(Icons.search), const SizedBox(width: 8),
          Expanded(child: TextField(controller: searchCtrl, decoration: const InputDecoration(hintText: 'Buscar producto por nombre o código...', border: InputBorder.none))),
          IconButton(onPressed: onMic, icon: const Icon(Icons.mic)),
        ]),
      )),
    ]);
  }
}

class _VentasPage extends StatefulWidget {
  final Repo repo; final TabController ventasTabs; final List<List<LineaVenta>> carritos; final TextEditingController searchCtrl;
  final void Function(Producto) onToggleFav; final void Function(Producto) onAdd;
  final VoidCallback onEscanear; final VoidCallback onCobrar; final VoidCallback onVaciarCarrito;
  const _VentasPage({super.key, required this.repo, required this.ventasTabs, required this.carritos, required this.searchCtrl, required this.onToggleFav, required this.onAdd, required this.onEscanear, required this.onCobrar, required this.onVaciarCarrito});
  @override State<_VentasPage> createState() => _VentasPageState();
}

class _VentasPageState extends State<_VentasPage> {
  int tab = 0;
  @override void initState(){ super.initState(); widget.searchCtrl.addListener(_onSearch); }
  @override void dispose(){ widget.searchCtrl.removeListener(_onSearch); super.dispose(); }
  void _onSearch(){ final p = widget.repo.porSkuExacto(widget.searchCtrl.text); if(p!=null){ widget.onAdd(p); widget.searchCtrl.clear(); setState((){});} else { setState((){});} }
  @override Widget build(BuildContext context) {
    final productos = widget.repo.buscar(widget.searchCtrl.text, tab: tab);
    return Row(children: [
      Expanded(flex: 6, child: Column(children: [
        const SizedBox(height: 8), _TabsProductos(onChanged: (i)=>setState(()=>tab=i)), const SizedBox(height: 8),

        Expanded(child: _GridProductos(productos: productos, onAdd: widget.onAdd, onToggleFav: widget.onToggleFav,)),

      ])),
      Container(width: 1, color: Colors.grey.shade300),
      Expanded(flex: 4, child: Column(children: [
        TabBar(controller: widget.ventasTabs, tabs: const [Tab(text: 'VENTA 1'), Tab(text: 'VENTA 2'), Tab(text: 'VENTA 3')], onTap: (_)=>setState((){})),
        Expanded(
          child: TabBarView(
            controller: widget.ventasTabs,
            children: List.generate(3, (i) => _CarritoView(
              lineas: widget.carritos[i],
              onDelete: (ix) => setState(() => widget.carritos[i].removeAt(ix)),
              onCantidadChange: (ix, nueva) {
                final l = widget.carritos[i][ix];
                final p = l.producto;

                double valor = (nueva.isNaN ? l.cantidad : nueva);
                if (valor < 0) valor = 0;

                final max = p.esGranel
                    ? p.stock.toDouble()
                    : p.stock.floorToDouble();

                valor = valor.clamp(0, max);
                setState(() => l.cantidad = valor);
              }
            )),
          ),
        ),
        _BarraCobro(
          subtotal: _subtotal(widget.carritos[widget.ventasTabs.index]),
          numProductos: _numProductos(widget.carritos[widget.ventasTabs.index]),
          onEscanear: widget.onEscanear, onLimpiar: widget.onVaciarCarrito, onCobrar: widget.onCobrar,
        ),
      ])),
    ]);
  }
  int _numProductos(List<LineaVenta> l)=> l.fold(0, (a,e)=>a+e.cantidad.toInt());
  double _subtotal(List<LineaVenta> l)=> l.fold(0.0, (a,e)=>a+e.subtotal);

}

class _TabsProductos extends StatelessWidget {
  final ValueChanged<int> onChanged; const _TabsProductos({required this.onChanged});
  @override Widget build(BuildContext context) {
    return DefaultTabController(length: 3, child: Builder(builder: (context) {
      return Column(children: [ TabBar(tabs: const [Tab(text: 'Más vendidos'), Tab(text: 'Favoritos'), Tab(text: 'Granel')], onTap: (i)=>onChanged(i)), ]);
    }));
  }
}

class _GridProductos extends StatelessWidget {
  final List<Producto> productos; 
  final void Function(Producto) onAdd; 
  final void Function(Producto) onToggleFav; 

  const _GridProductos({
    super.key,
    required this.productos,
    required this.onAdd,
    required this.onToggleFav,
  });

  Widget _img(Producto p) {
    if (p.imageBase64 != null && p.imageBase64!.isNotEmpty) { final bytes = base64Decode(p.imageBase64!); return Image.memory(bytes, fit: BoxFit.cover); }
    if (p.imageUrl == null || p.imageUrl!.isEmpty) { return const Center(child: Icon(Icons.inventory_2, size: 48)); }
    return Image.network(p.imageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___)=> const Center(child: Icon(Icons.broken_image)));
  }
  @override Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, cts) {
      final cross = (cts.maxWidth / 260).floor().clamp(1, 5);
      return GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cross, childAspectRatio: 0.74, crossAxisSpacing: 12, mainAxisSpacing: 12),
        itemCount: productos.length,
        itemBuilder: (_, i) {
          final p = productos[i];
          final agotado = p.stock <= 0;
          return Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: agotado ? null : () => onAdd(p), // deshabilita tap si está agotado
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        // imagen
                        Positioned.fill(child: _img(p)),
                        // favorito
                        Positioned(
                          top: 8, left: 8,
                          child: IconButton(
                            icon: Icon(p.fav ? Icons.favorite : Icons.favorite_border,
                                color: p.fav ? Colors.red : null),
                            onPressed: () => onToggleFav(p),
                          ),
                        ),
                        const Positioned(top: 8, right: 8, child: Icon(Icons.more_vert)),
                        // 🔴 CINTILLO "AGOTADO"
                        if (agotado)
                          Positioned.fill(
                            child: Container(
                              color: Colors.black.withOpacity(0.45),
                              alignment: Alignment.center,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade700,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'AGOTADO',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // texto
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.nombre, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(child: Text(p.presentacion, maxLines: 1, overflow: TextOverflow.ellipsis)),
                            Text('\$${p.precioVenta.toStringAsFixed(2)}',
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        // 👇 opcional: mostrar stock
                        Text('Stock: ${p.stock}',
                        style: TextStyle(color: agotado ? Colors.red : Colors.black54, fontSize: 12
                        )),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    });
  }
}

class _CarritoView extends StatelessWidget {
  final List<LineaVenta> lineas; final void Function(int) onDelete; final void Function(int,double) onCantidadChange;
  const _CarritoView({required this.lineas, required this.onDelete, required this.onCantidadChange});
  @override Widget build(BuildContext context) {
    if (lineas.isEmpty) return const Center(child: Text('Agrega productos desde el catálogo'));
    return ListView.separated(itemCount: lineas.length, separatorBuilder: (_, __)=> const Divider(height: 1), itemBuilder: (_, i) {
      final l = lineas[i];
      final qtyTxt = l.producto.esGranel ? l.cantidad.toStringAsFixed(3) : l.cantidad.toInt().toString();
      return ListTile(
        title: Text(l.producto.nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('SKU: ${l.producto.sku} • PPU: \$${l.producto.precioVenta.toStringAsFixed(2)}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Eliminar este producto',
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => onDelete(i),
            ),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: () {
                final nueva = (l.cantidad - 1).clamp(0, 999).toDouble();
                if (nueva <= 0) onDelete(i);
                else onCantidadChange(i, nueva);
              },
            ),
            SizedBox(
              width: 50,
              child: TextField(
                textAlign: TextAlign.center,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                controller: TextEditingController(
                  text: l.producto.esGranel
                      ? l.cantidad.toStringAsFixed(3)
                      : l.cantidad.toStringAsFixed(0),
                ),
                onSubmitted: (v) {
                  final parsed = double.tryParse(v) ?? l.cantidad;
                  onCantidadChange(i, parsed); // ← el clamp ocurre en _VentasPage
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () {
              final max = l.producto.esGranel
                  ? l.producto.stock.toDouble()
                  : l.producto.stock.floorToDouble();
              double nueva = l.cantidad + 1;
              if (!l.producto.esGranel) nueva = nueva.floorToDouble();
              if (nueva > max) nueva = max; // ← tope por stock real
              onCantidadChange(i, nueva);      
              },
            )
        ]),
      );
    });
  }
}

class _BarraCobro extends StatelessWidget {
  final double subtotal; final int numProductos; final VoidCallback onEscanear; final VoidCallback onLimpiar; final VoidCallback onCobrar;
  const _BarraCobro({super.key, required this.subtotal, required this.numProductos, required this.onEscanear, required this.onLimpiar, required this.onCobrar});
  @override Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
        color: Theme.of(context).colorScheme.surface,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: Wrap(spacing: 16, children: [
              Text('Subtotal: \$${subtotal.toStringAsFixed(2)}', style: TextStyle(color: Colors.grey[800], fontWeight: FontWeight.w600)),
              Text('Productos: $numProductos', style: TextStyle(color: Colors.grey[800], fontWeight: FontWeight.w600)),
              Text('Total: \$${subtotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w800)),
            ])),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            const Spacer(),
            FilledButton.icon(
              onPressed: onCobrar,
              icon: const Icon(Icons.receipt_long),
              label: const Text('Cobrar / Ticket'),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1B5E20)),
            ),
          ]),
        ],
      ),
    );
  }
}

// ===================== ADMIN / INVENTARIO =====================

class AdminHome extends StatelessWidget {
  final Repo repo;
  const AdminHome({super.key, required this.repo});

  @override
  Widget build(BuildContext context) {
    final int alertas = repo.productos.where((p) => p.visible && p.stock <= p.alertaMin).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Administración')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.inventory_2, size: 28),
                    if (alertas > 0)
                      Positioned(
                        right: -6,
                        top: -6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Color(0xFFD32F2F),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$alertas',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                  ],
                ),
                title: Text(
                  'Inventario${alertas > 0 ? " ($alertas con alerta)" : ""}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text('Ver, editar, ajustar y agregar productos'),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => InventarioScreen(repo: repo))),
                      child: const Text('Abrir'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => InventarioScreen(repo: repo))),
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar'),
                    ),
                  ],
                ),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => InventarioScreen(repo: repo))),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: const Icon(Icons.query_stats, size: 28),
                title: const Text('Reportes', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('KPIs, Top productos, rangos de fecha y PDF'),
                trailing: FilledButton.tonal(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReportesScreen(repo: repo))),
                  child: const Text('Abrir'),
                ),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReportesScreen(repo: repo))),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: Icon(repo.corteAbierto != null ? Icons.play_circle : Icons.stop_circle, size: 28, color: repo.corteAbierto != null ? Colors.green : null),
                title: Text(
                  'Cortes ${repo.corteAbierto != null ? "(abierto)" : ""}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text('Abrir, cerrar y reportar ventas por corte'),
                trailing: Wrap(spacing: 8, children: [
                  if (repo.corteAbierto == null)
                    FilledButton.tonal(onPressed: () async { await repo.abrirCorte(); }, child: const Text('Abrir corte')),
                  if (repo.corteAbierto != null)
                    FilledButton.tonal(onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => CortesScreen(repo: repo)));
                    }, child: const Text('Ver corte')),
                ]),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CortesScreen(repo: repo))),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: const Icon(Icons.compare_arrows, size: 28),
                title: const Text('Movimientos de Inventario', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Entradas, salidas, ajustes y ventas'),
                trailing: FilledButton.tonal(onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => MovimientosScreen(repo: repo)));
                }, child: const Text('Abrir')),
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => MovimientosScreen(repo: repo)));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class ReportesScreen extends StatefulWidget {
  final Repo repo;
  const ReportesScreen({super.key, required this.repo});
  @override
  State<ReportesScreen> createState() => _ReportesScreenState();
}

enum RangoPreset { sieteDias, unMes, tresMeses, personalizado }
enum TabProductos { menorRotacion, masVendidos, mayorUtilidad }

class _ReportesScreenState extends State<ReportesScreen> {
  // Estado UI
  RangoPreset _preset = RangoPreset.tresMeses;
  DateTimeRange? _custom;
  TabProductos _tab = TabProductos.menorRotacion;

  // Config comisiones (editable)
  final TextEditingController _tasaComCtrl = TextEditingController(text: '0.00'); // % (ej. 1.8)
  double get _tasaCom => (double.tryParse(_tasaComCtrl.text) ?? 0) / 100.0;

  DateTimeRange _rangoActual(){
    final now = DateTime.now();
    switch (_preset) {
      case RangoPreset.sieteDias:
        final ini = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
        final fin = DateTime(now.year, now.month, now.day, 23, 59, 59);
        return DateTimeRange(start: ini, end: fin);
      case RangoPreset.unMes:
        final ini = DateTime(now.year, now.month, 1);
        final fin = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
        return DateTimeRange(start: ini, end: fin);
      case RangoPreset.tresMeses:
        final ini = DateTime(now.year, now.month - 2, 1);
        final fin = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
        return DateTimeRange(start: ini, end: fin);
      case RangoPreset.personalizado:
        return _custom ??
            DateTimeRange(
              start: DateTime(now.year, now.month, now.day),
              end: DateTime(now.year, now.month, now.day, 23, 59, 59),
            );
    }
  }

  // --------- Cálculos ----------
  List<Venta> _ventasRango() {
    final r = _rangoActual();
    return widget.repo.ventas.where((v) =>
      v.fecha.isAfter(r.start.subtract(const Duration(microseconds: 1))) &&
      v.fecha.isBefore(r.end.add(const Duration(microseconds: 1)))
    ).toList();
  }

  // Totales principales
  ({double total, double utilidad, double comisiones, int tickets}) _kpis() {
    final vs = _ventasRango();
    double total = 0, utilidad = 0;
    for (final v in vs) {
      total += v.total;
      for (final l in v.lineas) {
        // Precio compra: tomamos el actual del repo (si cambió, es aproximado)
        final ref = widget.repo.productos.firstWhere(
          (p) => p.id == l.producto.id,
          orElse: () => l.producto,
        );
        final costoUnit = ref.precioCompra;
        utilidad += (l.producto.precioVenta - costoUnit) * l.cantidad;
      }
    }
    final comisiones = total * _tasaCom;
    return (total: total, utilidad: utilidad, comisiones: comisiones, tickets: vs.length);
  }

  // Agregados por producto
  List<_AggProducto> _agregadosPorProducto() {
    final Map<String, _AggProducto> map = {};
    for (final v in _ventasRango()) {
      for (final l in v.lineas) {
        final id = l.producto.id;
        final ref = widget.repo.productos.firstWhere(
          (p) => p.id == id,
          orElse: () => l.producto,
        );
        final costoUnit = ref.precioCompra;
        final ingreso = l.subtotal;
        final utilidad = (l.producto.precioVenta - costoUnit) * l.cantidad;
        final e = map.putIfAbsent(
          id,
          () => _AggProducto(
            id: id,
            nombre: l.producto.nombre,
            presentacion: l.producto.presentacion,
          ),
        );
        e.unidades += l.cantidad;
        e.venta += ingreso;
        e.utilidad += utilidad;
      }
    }
    return map.values.toList();
  }

  // Orden según pestaña
  List<_AggProducto> _ordenados() {
    final list = _agregadosPorProducto();
    switch (_tab) {
      case TabProductos.menorRotacion:
        list.sort((a, b) => a.unidades.compareTo(b.unidades)); // asc
        break;
      case TabProductos.masVendidos:
        list.sort((a, b) => b.unidades.compareTo(a.unidades)); // desc
        break;
      case TabProductos.mayorUtilidad:
        list.sort((a, b) => b.utilidad.compareTo(a.utilidad)); // desc
        break;
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final r = _rangoActual();
    final k = _kpis();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reporte de ventas'),
        actions: [
          IconButton(
          tooltip: 'Exportar PDF',
          icon: const Icon(Icons.picture_as_pdf_outlined),
          onPressed: _exportarPdf, // ← usa el método nuevo
        ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${r.end.toString().substring(0, 10)}  ${TimeOfDay.fromDateTime(DateTime.now()).format(context)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            // Franja: nota + filtros "Ver por"
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Debes de mantener actualizado tu inventario para obtener un mejor resultado',
                    style: TextStyle(color: Colors.black.withOpacity(0.6)),
                  ),
                ),
                const SizedBox(width: 12),
                const Text('Ver por'),
                const SizedBox(width: 8),
                DropdownButton<RangoPreset>(
                  value: _preset,
                  onChanged: (v) async {
                    if (v == null) return;
                    if (v == RangoPreset.personalizado) {
                      final sel = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(DateTime.now().year - 2),
                        lastDate: DateTime(DateTime.now().year + 1),
                        initialDateRange: _rangoActual(),
                      );
                      if (sel != null) {
                        setState(() { _preset = v; _custom = sel; });
                      }
                    } else {
                      setState(() { _preset = v; });
                    }
                  },
                  items: const [
                    DropdownMenuItem(value: RangoPreset.sieteDias, child: Text('7 días')),
                    DropdownMenuItem(value: RangoPreset.unMes, child: Text('1 mes')),
                    DropdownMenuItem(value: RangoPreset.tresMeses, child: Text('3 meses')),
                    DropdownMenuItem(value: RangoPreset.personalizado, child: Text('Personalizado')),
                  ],
                ),
                const SizedBox(width: 12),
                // Tasa de comisión (%)
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _tasaComCtrl,
                    onSubmitted: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Comisión %',
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // KPIs (3 tarjetas)
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _KpiCard(title: 'VENTA TOTAL', value: _fmtMoney(k.total), icon: Icons.shopping_bag),
                _KpiCard(title: 'GANANCIAS / UTILIDAD EN POS', value: _fmtMoney(k.utilidad), icon: Icons.ssid_chart),
                _KpiCard(title: 'COMISIONES', value: _fmtMoney(k.comisiones), icon: Icons.receipt_long),
              ],
            ),

            const SizedBox(height: 20),

            // Gráfica de barras
            const Text('Cantidad de ventas', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            _BarChart(
              series: const ['Transacciones', 'POS', 'Adquiriente'],
              // Para simplificar: Transacciones = #tickets (lo llevamos a dinero como tickets*promedio para escalar) 
              // pero aquí lo mostramos como conteo sobre el eje derecho en etiqueta.
              values: [k.tickets.toDouble(), k.total, k.comisiones],
              valueLabels: [
                '${k.tickets}',
                _fmtMoney(k.total),
                _fmtMoney(k.comisiones),
              ],
            ),

            const SizedBox(height: 20),

            // Panel "Mis productos" (tabs + pastel + tabla)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Izquierda: tabs + pie
                Expanded(
                  child: Card(
                    elevation: 0.5,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Mis productos', style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          SegmentedButton<TabProductos>(
                            segments: const [
                              ButtonSegment(value: TabProductos.menorRotacion, label: Text('MENOR ROTACIÓN')),
                              ButtonSegment(value: TabProductos.masVendidos, label: Text('MÁS VENDIDOS')),
                              ButtonSegment(value: TabProductos.mayorUtilidad, label: Text('MAYOR UTILIDAD')),
                            ],
                            selected: {_tab},
                            onSelectionChanged: (s) => setState(() => _tab = s.first),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 220,
                            child: _PieChart(
                              // Para el pastel usamos top 6 del criterio actual
                              entries: _ordenados().take(6).map((e) => (e.nombre, e.unidades)).toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                // Derecha: tabla de productos (ordenada según tab)
                Expanded(
                  child: Card(
                    elevation: 0.5,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Expanded(child: Text('Lugar')),
                              Expanded(flex: 4, child: Text('Nombre')),
                              Expanded(child: Text('Unidades')),
                              Expanded(child: Text('Venta')),
                            ],
                          ),
                          const Divider(),
                          ..._ordenados().take(8).indexed.map((e) {
                            final idx = e.$1 + 1;
                            final p = e.$2;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  const SizedBox(width: 4),
                                  Expanded(child: Text('$idx')),
                                  Expanded(flex: 4, child: Text('${p.nombre}${p.presentacion.isNotEmpty ? ' ${p.presentacion}' : ''}', overflow: TextOverflow.ellipsis)),
                                  Expanded(child: Text(_fmtQty(p.unidades), textAlign: TextAlign.right)),
                                  Expanded(child: Text(_fmtMoney(p.venta), textAlign: TextAlign.right)),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

Future<void> _exportarPdf() async {
  final r = _rangoActual();
  final k = _kpis();
  final top = _ordenados().take(10).toList(); // según la pestaña activa

  String _d(DateTime d) => d.toString().substring(0, 10);
  String _m(double v)   => '\$${v.toStringAsFixed(2)}';
  String _q(double v)   => (v == v.roundToDouble()) ? v.toInt().toString() : v.toStringAsFixed(3);

  final doc = pw.Document();

  doc.addPage(
    pw.MultiPage(
      pageFormat: pwlib.PdfPageFormat.a4,
      build: (ctx) => [
        pw.Header(
          level: 0,
          child: pw.Text(
            'Mini Súper Garza — Reporte de Ventas',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.Text('Rango: ${_d(r.start)} — ${_d(r.end)}'),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(width: 0.2),
          columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(2)},
          children: [
            pw.TableRow(children: [
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Venta total')),
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(_m(k.total))),
            ]),
            pw.TableRow(children: [
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Utilidad estimada')),
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(_m(k.utilidad))),
            ]),
            pw.TableRow(children: [
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Comisiones')),
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(_m(k.comisiones))),
            ]),
            pw.TableRow(children: [
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Tickets')),
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('${k.tickets}')),
            ]),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Text('Top productos', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(width: 0.2),
          columnWidths: const {
            0: pw.FlexColumnWidth(1),
            1: pw.FlexColumnWidth(6),
            2: pw.FlexColumnWidth(2),
            3: pw.FlexColumnWidth(2),
            4: pw.FlexColumnWidth(2),
          },
          children: [
            pw.TableRow(children: [
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('#', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Producto', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Unidades', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Venta', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Utilidad', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
            ]),
            ...top.indexed.map((e) {
              final i = e.$1 + 1;
              final p = e.$2;
              final nombre = p.presentacion.isNotEmpty ? '${p.nombre} ${p.presentacion}' : p.nombre;
              return pw.TableRow(children: [
                pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('$i')),
                pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(nombre)),
                pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(_q(p.unidades))),
                pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(_m(p.venta))),
                pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(_m(p.utilidad))),
              ]);
            }),
          ],
        ),
      ],
    ),
  );

  await Printing.layoutPdf(onLayout: (format) async => doc.save());
}

}

// ---- Modelillos y helpers locales ----
class _AggProducto {
  final String id;
  final String nombre;
  final String presentacion;
  double unidades = 0;
  double venta = 0;
  double utilidad = 0;
  _AggProducto({required this.id, required this.nombre, required this.presentacion});
}

String _fmtMoney(double v) => '\$${v.toStringAsFixed(2)}';
String _fmtQty(double q) => (q == q.roundToDouble()) ? q.toInt().toString() : q.toStringAsFixed(3);

// ---- Widgets UI: KPI card, Bar chart, Pie chart (sin dependencias) ----
class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  const _KpiCard({required this.title, required this.value, required this.icon});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Card(
        elevation: 0.5,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarChart extends StatelessWidget {
  final List<String> series;
  final List<double> values;
  final List<String> valueLabels;
  const _BarChart({required this.series, required this.values, required this.valueLabels});
  @override
  Widget build(BuildContext context) {
    final max = (values.isEmpty ? 1.0 : values.reduce((a, b) => a > b ? a : b)) * 1.2;
    return Card(
      elevation: 0.5,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: 220,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(values.length, (i) {
              final h = (values[i] / (max == 0 ? 1 : max)) * 160.0;
              return Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(valueLabels[i], style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Container(height: h, width: 28, color: Theme.of(context).colorScheme.primary.withOpacity(0.85)),
                    const SizedBox(height: 8),
                    Text(series[i]),
                  ],
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _PieChart extends StatelessWidget {
  // entries: (label, value)
  final List<(String, double)> entries;
  const _PieChart({required this.entries});
  @override
  Widget build(BuildContext context) {
    final total = entries.fold<double>(0, (a, e) => a + (e.$2 <= 0 ? 0 : e.$2));
    return CustomPaint(
      painter: _PiePainter(entries, total, Theme.of(context).colorScheme.primary),
      child: Center(
        child: Text(
          total <= 0 ? 'Sin datos' : '',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _PiePainter extends CustomPainter {
  final List<(String, double)> entries;
  final double total;
  final Color base;
  _PiePainter(this.entries, this.total, this.base);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: size.shortestSide * 0.42);
    final paint = Paint()..style = PaintingStyle.fill;
    double start = -3.14159 / 2; // arriba

    // Pastel
    for (var i = 0; i < entries.length; i++) {
      final v = entries[i].$2 <= 0 ? 0.0 : entries[i].$2;
      final sweep = total <= 0 ? 0.0 : (v / total) * 6.28318;
      paint.color = HSVColor.fromAHSV(1, (i * 45) % 360.0, 0.6, 0.9).toColor();
      canvas.drawArc(rect, start, sweep, true, paint);
      start += sweep;
    }
    // Donut (agujero)
    final hole = Paint()..color = Colors.white;
    canvas.drawCircle(size.center(Offset.zero), size.shortestSide * 0.22, hole);
  }

  @override
  bool shouldRepaint(covariant _PiePainter oldDelegate) =>
      oldDelegate.entries != entries || oldDelegate.total != total;
}


class TotalesHoyScreen extends StatelessWidget {
  final Repo repo; const TotalesHoyScreen({super.key, required this.repo});
  @override Widget build(BuildContext context) {
    final hoy = DateTime.now(); final total = repo.totalDelDia(hoy);
    return Scaffold(appBar: AppBar(title: const Text('Totales de Hoy')), body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text('Fecha: ${hoy.toString().substring(0, 10)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8), Text('\$${total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900)),
    ])));
  }
}

class InventarioScreen extends StatefulWidget { final Repo repo; const InventarioScreen({super.key, required this.repo}); @override State<InventarioScreen> createState() => _InventarioScreenState(); }
class _InventarioScreenState extends State<InventarioScreen> {
  final TextEditingController _search = TextEditingController();
  String _filtroVer = 'Todos';
  late ProductosDataSource _ds;
  int _rowsPerPage = PaginatedDataTable.defaultRowsPerPage;
  int _sortColumnIndex = 2; bool _sortAsc = true; // nombre

  @override void initState() { super.initState(); _ds = ProductosDataSource(context, widget.repo, _filtered(), onChanged: _refreshFromSource); widget.repo.addListener(_onRepoChange); }
  void _onRepoChange() { setState(() { _ds = ProductosDataSource(context, widget.repo, _filtered(), onChanged: _refreshFromSource); }); }
  void _refreshFromSource() { setState(() { _ds = ProductosDataSource(context, widget.repo, _filtered(), onChanged: _refreshFromSource); }); }
  @override void dispose() { widget.repo.removeListener(_onRepoChange); super.dispose(); }

  List<Producto> _filtered() {
    final q = _search.text.trim().toLowerCase();
    Iterable<Producto> src = widget.repo.productos;
    if (_filtroVer == 'Visibles') src = src.where((p) => p.visible);
    if (_filtroVer == 'Ocultos') src = src.where((p) => !p.visible);
    if (_filtroVer == 'Con alerta') src = src.where((p) => p.stock <= p.alertaMin);
    if (q.isNotEmpty) src = src.where((p) => p.nombre.toLowerCase().contains(q) || p.sku.toLowerCase().contains(q));
    final list = src.toList(); _sort(list); return list;
  }

  void _sort(List<Producto> list) {
    int compare<T extends Comparable>(T a, T b) => a.compareTo(b);
    switch (_sortColumnIndex) {
      // 0 Fav, 1 Tipo, 2 Nombre, 3 SKU, 4 PrecioCompra, 5 PrecioVenta, 6 Stock
      case 2: list.sort((a,b)=>compare(a.nombre.toLowerCase(), b.nombre.toLowerCase())); break;
      case 3: list.sort((a,b)=>compare(a.sku.toLowerCase(), b.sku.toLowerCase())); break;
      case 4: list.sort((a,b)=>compare(a.precioCompra, b.precioCompra)); break;
      case 5: list.sort((a,b)=>compare(a.precioVenta, b.precioVenta)); break;
      case 6: list.sort((a,b)=>compare(a.stock, b.stock)); break;
      default: break;
    }
    if (!_sortAsc) list = list.reversed.toList();
  }

  void _onSort(int columnIndex, bool asc) { setState(() { _sortColumnIndex = columnIndex; _sortAsc = asc; _ds = ProductosDataSource(context, widget.repo, _filtered(), onChanged: _refreshFromSource); }); }

  @override
  Widget build(BuildContext context) {



    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventario'), 
        actions: [
          Row(children: [
            const Text('Ver: ', style: TextStyle(fontWeight: FontWeight.w600)),
            DropdownButton<String>(value: _filtroVer, onChanged: (v) => setState(() { _filtroVer = v ?? 'Todos'; _ds = ProductosDataSource(context, widget.repo, _filtered(), onChanged: _refreshFromSource); }), items: const [
              DropdownMenuItem(value: 'Todos', child: Text('Todos')),
              DropdownMenuItem(value: 'Visibles', child: Text('Visibles')),
              DropdownMenuItem(value: 'Ocultos', child: Text('Ocultos')),
              DropdownMenuItem(value: 'Con alerta', child: Text('Con alerta')),
            ]),
            const SizedBox(width: 12),
            FilledButton.icon(onPressed: _abrirAgregarProducto, icon: const Icon(Icons.add), label: const Text('Agregar Producto')),
            const SizedBox(width: 12),
          ]),
          IconButton(
            tooltip: 'Sincronizar desde Google Sheets',
            icon: const Icon(Icons.sync),
            onPressed: () async {
              const csvUrl = 'https://docs.google.com/spreadsheets/d/e/2PACX-1vSA82CpM6K1ZyZPEOm6Mj7WJbyPKvw9ZL2ZcL-iadf4PHuepr7JW-SgU2WwUIs1hc7qbnsxIgAImKwh/pub?gid=0&single=true&output=csv';
              try {
                final (a, n) = await widget.repo.syncProductosDesdeCsv(csvUrl);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Sincronizado: $a actualizados, $n nuevos')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error al sincronizar: $e')),
                  );
                }
              }
            },
          ),
        ],

      bottom: PreferredSize(preferredSize: const Size.fromHeight(56), child: Padding(padding: const EdgeInsets.fromLTRB(16,0,16,12), child: TextField(
        controller: _search, onChanged: (_)=> setState(() { _ds = ProductosDataSource(context, widget.repo, _filtered(), onChanged: _refreshFromSource); }),
        decoration: InputDecoration(filled: true, hintText: 'Buscar producto por nombre o código...', prefixIcon: const Icon(Icons.search), suffixIcon: IconButton(icon: const Icon(Icons.mic), onPressed: () {}), border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)), isDense: true,),
      )))),
      body: SingleChildScrollView(child: PaginatedDataTable(
        header: const Text(''), rowsPerPage: _rowsPerPage, onRowsPerPageChanged: (v) { if (v != null) setState(() => _rowsPerPage = v); },
        sortColumnIndex: _sortColumnIndex, sortAscending: _sortAsc,
        columns: [
          const DataColumn(label: Text('Fav')),
          const DataColumn(label: Text('Tipo')), // nueva
          DataColumn(label: const Text('Nombre'), onSort: (i, asc) => _onSort(2, asc)),
          DataColumn(label: const Text('SKU'), onSort: (i, asc) => _onSort(3, asc)),
          DataColumn(label: const Text('Precio Compra'), numeric: true, onSort: (i, asc) => _onSort(4, asc)),
          DataColumn(label: const Text('Precio Venta'), numeric: true, onSort: (i, asc) => _onSort(5, asc)),
          DataColumn(label: const Text('Stock'), numeric: true, onSort: (i, asc) => _onSort(6, asc)),
          const DataColumn(label: Text('Alerta Mín. Inv.')),
          const DataColumn(label: Text('Img')),
          const DataColumn(label: Text('Visible')),
          const DataColumn(label: Text('Editar')),
          const DataColumn(label: Text('Ajustar')),
          const DataColumn(label: Text('Eliminar')),
        ],
        source: _ds, showFirstLastButtons: true, columnSpacing: 20,
      )),
    );
  }

  Future<void> _pickImageToBase64(TextEditingController target) async {
    final picker = ImagePicker();
    final XFile? file = await showModalBottomSheet<XFile?>(
      context: context, showDragHandle: true,
      builder: (_) => SafeArea(child: Wrap(children: [
        ListTile(leading: const Icon(Icons.photo_camera), title: const Text('Tomar foto (cámara)'), onTap: () async { final x = await picker.pickImage(source: ImageSource.camera, imageQuality: 80); if (context.mounted) Navigator.pop(context, x); }),
        ListTile(leading: const Icon(Icons.photo_library), title: const Text('Elegir de galería'), onTap: () async { final x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80); if (context.mounted) Navigator.pop(context, x); }),
      ])),
    );
    if (file != null) { final bytes = await file.readAsBytes(); target.text = base64Encode(bytes); }
  }

  void _abrirAgregarProducto() {
    final formKey = GlobalKey<FormState>();
    final nombre = TextEditingController(); final sku = TextEditingController(); final present = TextEditingController();
    final pc = TextEditingController(text: '0'); final pv = TextEditingController(text: '0'); final stk = TextEditingController(text: '0'); final alerta = TextEditingController(text: '0');
    final imageUrl = TextEditingController(); final imageB64 = TextEditingController();
    final esGranel = ValueNotifier<bool>(false); // selector tipo

    showDialog(context: context, builder: (ctx)=> AlertDialog(title: const Text('Agregar Producto'), content: SizedBox(width: 480, child: Form(key: formKey, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(child: TextFormField(controller: nombre, decoration: const InputDecoration(labelText: 'Nombre'), validator: (v)=> (v==null||v.trim().isEmpty)?'Requerido':null)),
        const SizedBox(width: 8),
        Expanded(child: TextFormField(controller: sku, decoration: const InputDecoration(labelText: 'SKU'), validator: (v)=> (v==null||v.trim().isEmpty)?'Requerido':null)),
      ]),
      TextFormField(controller: present, decoration: const InputDecoration(labelText: 'Presentación (ej. 500 ml, 1 kg)')),
      Row(children: [
        Expanded(child: TextFormField(controller: pc, decoration: const InputDecoration(labelText: 'Precio compra'), keyboardType: TextInputType.number)),
        const SizedBox(width: 8),
        Expanded(child: TextFormField(controller: pv, decoration: const InputDecoration(labelText: 'Precio venta'), keyboardType: TextInputType.number)),
      ]),
      Row(children: [
        Expanded(child: TextFormField(controller: stk, decoration: const InputDecoration(labelText: 'Stock'), keyboardType: TextInputType.number)),
        const SizedBox(width: 8),
        Expanded(child: TextFormField(controller: alerta, decoration: const InputDecoration(labelText: 'Alerta mínima'), keyboardType: TextInputType.number)),
      ]),
      const SizedBox(height: 8),
      Align(alignment: Alignment.centerLeft, child: ValueListenableBuilder<bool>(valueListenable: esGranel, builder: (_, v, __)=> SegmentedButton<bool>(segments: const [
        ButtonSegment(value: false, label: Text('Unitario')),
        ButtonSegment(value: true,  label: Text('A granel')),
      ], selected: {v}, onSelectionChanged: (s)=> esGranel.value = s.first,))),
      const SizedBox(height: 8),
      Row(children: [ Expanded(child: TextFormField(controller: imageUrl, decoration: const InputDecoration(labelText: 'URL de imagen (opcional)'))), ]),
      const SizedBox(height: 8),
      Row(children: [ Expanded(child: TextFormField(controller: imageB64, decoration: const InputDecoration(labelText: 'Imagen (base64 auto)'), readOnly: true,)), const SizedBox(width: 8), FilledButton.tonal(onPressed: () => _pickImageToBase64(imageB64), child: const Text('Cámara/Galería')), ]),
    ])))),
    actions: [ TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Cancelar')),
      FilledButton(onPressed: (){ if (formKey.currentState!.validate()) {
        widget.repo.addProducto(Producto(id: 'p${DateTime.now().microsecondsSinceEpoch}', nombre: nombre.text.trim(), sku: sku.text.trim(), presentacion: present.text.trim(),
          precioCompra: double.tryParse(pc.text) ?? 0, precioVenta: double.tryParse(pv.text) ?? 0, stock: int.tryParse(stk.text) ?? 0, alertaMin: double.tryParse(alerta.text) ?? 0,
          imageUrl: imageUrl.text.trim().isEmpty ? null : imageUrl.text.trim(), imageBase64: imageB64.text.trim().isEmpty ? null : imageB64.text.trim(),
          esGranel: esGranel.value,
        )); Navigator.pop(ctx); } }, child: const Text('Agregar')) ],
    )); }
}

class ProductosDataSource extends DataTableSource {
  final BuildContext ctx; final Repo repo; List<Producto> productos; final VoidCallback onChanged;
  ProductosDataSource(this.ctx, this.repo, this.productos, {required this.onChanged});

  @override DataRow? getRow(int index) {
    if (index >= productos.length) return null;
    final p = productos[index];
    Widget thumb;
    if (p.imageBase64 != null && p.imageBase64!.isNotEmpty) { thumb = Image.memory(base64Decode(p.imageBase64!), width: 40, height: 40, fit: BoxFit.cover); }
    else if (p.imageUrl != null && p.imageUrl!.isNotEmpty) { thumb = Image.network(p.imageUrl!, width: 40, height: 40, fit: BoxFit.cover); }
    else { thumb = const Icon(Icons.image_not_supported); }

    return DataRow.byIndex(index: index, cells: [
      DataCell(IconButton(icon: Icon(p.fav ? Icons.favorite : Icons.favorite_border, color: p.fav ? Colors.red : null), onPressed: () { repo.toggleFavorito(p); notifyListeners(); onChanged(); })),
      DataCell(Text(p.esGranel ? 'Granel' : 'Unitario')), // nueva
      DataCell(Text(p.nombre, maxLines: 1, overflow: TextOverflow.ellipsis)),
      DataCell(InkWell(onTap: (){}, child: Text(p.sku, style: const TextStyle(color: Colors.blue)))),
      DataCell(_editableNumber(p.precioCompra, (v){ p.precioCompra = v; repo.updateProducto(p); notifyListeners(); onChanged(); })),
      DataCell(_editableNumber(p.precioVenta, (v){ p.precioVenta = v; repo.updateProducto(p); notifyListeners(); onChanged(); })),
      DataCell(_editableInt(p.stock, (v){ p.stock = v; repo.updateProducto(p); notifyListeners(); onChanged(); })),
      DataCell(_editableNumber(p.alertaMin, (v){ p.alertaMin = v; repo.updateProducto(p); notifyListeners(); onChanged(); })),
      DataCell(thumb),
      DataCell(IconButton(icon: Icon(p.visible ? Icons.visibility : Icons.visibility_off), onPressed: (){ repo.toggleVisible(p); notifyListeners(); onChanged(); })),
      DataCell(IconButton(icon: const Icon(Icons.edit), onPressed: ()=>_editarProducto(p))),
      DataCell(IconButton(icon: const Icon(Icons.swap_vert), onPressed: ()=>_ajustarProducto(p))),
      DataCell(IconButton(icon: const Icon(Icons.delete_forever, color: Colors.red), onPressed: ()=>_eliminarProducto(p))), // eliminar
    ]);
  }

  void _eliminarProducto(Producto p) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Eliminar producto'),
        content: Text('¿Eliminar "${p.nombre}"? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(dialogCtx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: ()=>Navigator.pop(dialogCtx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok == true) { repo.removeProducto(p); notifyListeners(); onChanged(); }
  }

  void _editarProducto(Producto p) {
    final formKey = GlobalKey<FormState>();
    final nombre = TextEditingController(text: p.nombre);
    final sku = TextEditingController(text: p.sku);
    final present = TextEditingController(text: p.presentacion);
    final pc = TextEditingController(text: p.precioCompra.toString());
    final pv = TextEditingController(text: p.precioVenta.toString());
    final stk = TextEditingController(text: p.stock.toString());
    final alerta = TextEditingController(text: p.alertaMin.toString());
    final imageUrl = TextEditingController(text: p.imageUrl ?? '');
    final imageB64 = TextEditingController(text: p.imageBase64 ?? '');
    final esGranel = ValueNotifier<bool>(p.esGranel);

    Future<void> pick() async {
      final picker = ImagePicker();
      final XFile? file = await showModalBottomSheet<XFile?>(
        context: ctx, showDragHandle: true,
        builder: (_) => SafeArea(child: Wrap(children: [
          ListTile(leading: const Icon(Icons.photo_camera), title: const Text('Tomar foto (cámara)'), onTap: () async { final x = await picker.pickImage(source: ImageSource.camera, imageQuality: 80); if (ctx.mounted) Navigator.pop(ctx, x); },),
          ListTile(leading: const Icon(Icons.photo_library), title: const Text('Elegir de galería'), onTap: () async { final x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80); if (ctx.mounted) Navigator.pop(ctx, x); },),
        ])),
      );
      if (file != null) { final bytes = await file.readAsBytes(); imageB64.text = base64Encode(bytes); }
    }

    showDialog(context: ctx, builder: (dCtx)=> AlertDialog(title: const Text('Editar Producto'), content: SizedBox(width: 480, child: Form(key: formKey, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(child: TextFormField(controller: nombre, decoration: const InputDecoration(labelText:'Nombre'), validator:(v)=>(v==null||v.trim().isEmpty)?'Requerido':null)),
        const SizedBox(width: 8),
        Expanded(child: TextFormField(controller: sku, decoration: const InputDecoration(labelText:'SKU'), validator:(v)=>(v==null||v.trim().isEmpty)?'Requerido':null)),
      ]),
      TextFormField(controller: present, decoration: const InputDecoration(labelText:'Presentación')),
      Row(children: [
        Expanded(child: TextFormField(controller: pc, decoration: const InputDecoration(labelText:'Precio compra'), keyboardType: TextInputType.number)),
        const SizedBox(width: 8),
        Expanded(child: TextFormField(controller: pv, decoration: const InputDecoration(labelText:'Precio venta'), keyboardType: TextInputType.number)),
      ]),
      Row(children: [
        Expanded(child: TextFormField(controller: stk, decoration: const InputDecoration(labelText:'Stock'), keyboardType: TextInputType.number)),
        const SizedBox(width: 8),
        Expanded(child: TextFormField(controller: alerta, decoration: const InputDecoration(labelText:'Alerta mínima'), keyboardType: TextInputType.number)),
      ]),
      const SizedBox(height: 8),
      Align(alignment: Alignment.centerLeft, child: ValueListenableBuilder<bool>(valueListenable: esGranel, builder: (_, v, __)=> SegmentedButton<bool>(segments: const [
        ButtonSegment(value: false, label: Text('Unitario')),
        ButtonSegment(value: true,  label: Text('A granel')),
      ], selected: {v}, onSelectionChanged: (s)=> esGranel.value = s.first,))),
      const SizedBox(height: 8),
      TextFormField(controller: imageUrl, decoration: const InputDecoration(labelText:'URL de imagen (opcional)')),
      const SizedBox(height: 8),
      Row(children: [ Expanded(child: TextFormField(controller: imageB64, decoration: const InputDecoration(labelText: 'Imagen (base64 auto)'), readOnly: true )), const SizedBox(width: 8), FilledButton.tonal(onPressed: pick, child: const Text('Cámara/Galería')), ]),
    ])))), actions: [
      TextButton(onPressed: ()=>Navigator.pop(dCtx), child: const Text('Cancelar')),
      FilledButton(onPressed: (){ if (formKey.currentState!.validate()) {
        p.nombre = nombre.text.trim(); p.sku = sku.text.trim(); p.presentacion = present.text.trim();
        p.precioCompra = double.tryParse(pc.text) ?? p.precioCompra; p.precioVenta = double.tryParse(pv.text) ?? p.precioVenta;
        p.stock = int.tryParse(stk.text) ?? p.stock; p.alertaMin = double.tryParse(alerta.text) ?? p.alertaMin;
        p.imageUrl = imageUrl.text.trim().isEmpty ? null : imageUrl.text.trim(); p.imageBase64 = imageB64.text.trim().isEmpty ? null : imageB64.text.trim();
        p.esGranel = esGranel.value;
        repo.updateProducto(p); notifyListeners(); onChanged(); Navigator.pop(dCtx);
      }}, child: const Text('Guardar')),
    ]));
  }

  void _ajustarProducto(Producto p) {
    final tipo = ValueNotifier<String>('Sumar'); final qtyCtrl = TextEditingController(text: '1'); final motivoCtrl = TextEditingController();
    showModalBottomSheet(context: ctx, showDragHandle: true, builder: (bCtx)=> Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Ajustar stock (sobre el stock actual)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      Row(children: [ const Text('Tipo: '), const SizedBox(width: 12), ValueListenableBuilder<String>(valueListenable: tipo, builder: (_, v, __)=> SegmentedButton<String>(segments: const [ButtonSegment(value: 'Sumar', label: Text('Sumar al stock')), ButtonSegment(value: 'Restar', label: Text('Restar del stock'))], selected: {v}, onSelectionChanged: (s)=> tipo.value = s.first,)) ]),
      const SizedBox(height: 12), TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cantidad a sumar/restar')),
      const SizedBox(height: 12), TextField(controller: motivoCtrl, decoration: const InputDecoration(labelText: 'Motivo (opcional)')),
      const SizedBox(height: 16), Align(alignment: Alignment.centerRight, child: 
      FilledButton(onPressed: () async{
        final qty = int.tryParse(qtyCtrl.text) ?? 0; 
        if (qty > 0) {
          final antes = p.stock.toDouble();
          double delta;
          String tipoMov;

          final tipoSel = tipo.value;

          if (tipoSel == 'Sumar') {
            delta = qty.toDouble();
            p.stock = (p.stock + qty);
            tipoMov = 'ajuste+';
          } else {
            delta = -qty.toDouble();
            p.stock = (p.stock - qty).clamp(0, 1<<31);
            tipoMov = 'ajuste-';
          }

          repo.updateProducto(p);

          repo._logMovimiento(
            prod: p,
            delta: delta,
            tipo: tipoMov,
            motivo: motivoCtrl.text.trim().isEmpty ? null : motivoCtrl.text.trim(),
            antesOverride: antes,
            despuesOverride: p.stock.toDouble(),
          );
          await repo._saveMovs();
          notifyListeners();
          onChanged();
          Navigator.pop(bCtx);
        }
      }, child: const Text('Guardar'))),
    ])));
  }

  Widget _editableNumber(double value, ValueChanged<double> onSave) {
    final ctrl = TextEditingController(text: value.toStringAsFixed(2));
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Text('\$'),
      SizedBox(width: 70, child: TextField(controller: ctrl, keyboardType: TextInputType.number, decoration: const InputDecoration(isDense: true, border: InputBorder.none), onSubmitted: (v)=> onSave(double.tryParse(v) ?? value))),
    ]);
  }

  Widget _editableInt(int value, ValueChanged<int> onSave) {
    final ctrl = TextEditingController(text: value.toString());
    return SizedBox(width: 60, child: TextField(controller: ctrl, keyboardType: TextInputType.number, decoration: const InputDecoration(isDense: true, border: InputBorder.none), onSubmitted: (v)=> onSave(int.tryParse(v) ?? value)));
  }

  @override bool get isRowCountApproximate => false;
  @override int get rowCount => productos.length;
  @override int get selectedRowCount => 0;
}

class MovimientosScreen extends StatefulWidget {
  final Repo repo;
  const MovimientosScreen({super.key, required this.repo});

  @override
  State<MovimientosScreen> createState() => _MovimientosScreenState();
}

class _MovimientosScreenState extends State<MovimientosScreen> {
  String _tipo = 'Todos';
  String _q = '';
  DateTimeRange? _rango;

  List<MovimientoInv> _filtrados() {
    Iterable<MovimientoInv> src = widget.repo.movimientos;
    if (_tipo != 'Todos') src = src.where((m) => m.tipo == _tipo);
    if (_q.trim().isNotEmpty) {
      final s = _q.toLowerCase();
      src = src.where((m) =>
        m.nombreProducto.toLowerCase().contains(s) ||
        (m.motivo ?? '').toLowerCase().contains(s) ||
        (m.refVentaId ?? '').toLowerCase().contains(s));
    }
    if (_rango != null) {
      final a = _rango!.start;
      final b = _rango!.end;
      src = src.where((m) =>
        m.fecha.isAfter(a.subtract(const Duration(microseconds: 1))) &&
        m.fecha.isBefore(b.add(const Duration(microseconds: 1))));
    }
    return src.toList();
  }

  @override
  Widget build(BuildContext context) {
    final data = _filtrados();

    return Scaffold(
      appBar: AppBar(title: const Text('Movimientos de Inventario')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 🔹 Filtros superiores
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<String>(
                  value: _tipo,
                  onChanged: (v) => setState(() => _tipo = v ?? 'Todos'),
                  items: const [
                    DropdownMenuItem(value: 'Todos', child: Text('Todos')),
                    DropdownMenuItem(value: 'venta', child: Text('Ventas')),
                    DropdownMenuItem(value: 'entrada', child: Text('Entradas')),
                    DropdownMenuItem(value: 'salida', child: Text('Salidas')),
                    DropdownMenuItem(value: 'ajuste+', child: Text('Ajustes (+)')),
                    DropdownMenuItem(value: 'ajuste-', child: Text('Ajustes (–)')),
                  ],
                ),
                SizedBox(
                  width: 240,
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Buscar producto, motivo o ref.',
                    ),
                    onChanged: (v) => setState(() => _q = v),
                  ),
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.date_range),
                  onPressed: () async {
                    final hoy = DateTime.now();
                    final sel = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(hoy.year - 2),
                      lastDate: DateTime(hoy.year + 1),
                      initialDateRange: _rango,
                    );
                    if (sel != null) setState(() => _rango = sel);
                  },
                  label: Text(_rango == null
                      ? 'Rango: Todo'
                      : '${_rango!.start.toString().substring(0,10)} — ${_rango!.end.toString().substring(0,10)}'),
                ),
                TextButton(
                  onPressed: () => setState(() => _rango = null),
                  child: const Text('Limpiar rango'),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 🔹 Tabla de resultados
            Expanded(
              child: SingleChildScrollView(
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Fecha')),
                    DataColumn(label: Text('Tipo')),
                    DataColumn(label: Text('Producto')),
                    DataColumn(label: Text('Cant.'), numeric: true),
                    DataColumn(label: Text('Antes'), numeric: true),
                    DataColumn(label: Text('Después'), numeric: true),
                    DataColumn(label: Text('Motivo')),
                    DataColumn(label: Text('Ref. Venta')),
                  ],
                  rows: [
                    for (final m in data)
                      DataRow(cells: [
                        DataCell(Text(m.fecha.toString().substring(0,16))),
                        DataCell(Text(m.tipo)),
                        DataCell(Text(m.nombreProducto, overflow: TextOverflow.ellipsis)),
                        DataCell(Text(m.cantidad.toStringAsFixed(3))),
                        DataCell(Text(m.antes.toStringAsFixed(3))),
                        DataCell(Text(m.despues.toStringAsFixed(3))),
                        DataCell(Text(m.motivo ?? '—', overflow: TextOverflow.ellipsis)),
                        DataCell(Text(m.refVentaId ?? '—')),
                      ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===================== COBRO DIALOG =====================
class _CobroDialog extends StatefulWidget {
  final double total; const _CobroDialog({required this.total});
  @override State<_CobroDialog> createState() => _CobroDialogState();
}

class _CobroDialogState extends State<_CobroDialog> {
  final efectivoCtrl = TextEditingController(text: '0');
  @override Widget build(BuildContext context) {
    final total = widget.total; final efectivo = double.tryParse(efectivoCtrl.text) ?? 0; final cambio = (efectivo - total);
    return AlertDialog(title: const Text('Cobro en efectivo'), content: SizedBox(width: 360, child: Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ const Text('Total:', style: TextStyle(fontWeight: FontWeight.w700)), Text('\$${total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w900)), ]),
      const SizedBox(height: 8),
      TextField(controller: efectivoCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Efectivo recibido'), onChanged: (_)=> setState(() {})),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ const Text('Cambio:'), Text('\$${cambio < 0 ? 0 : cambio.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w700)), ]),
      if (cambio < 0) const SizedBox(height: 6),
      if (cambio < 0) const Align(alignment: Alignment.centerLeft, child: Text('Falta efectivo', style: TextStyle(color: Colors.red))),
    ])), actions: [
      TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('Cancelar')),
      FilledButton(onPressed: efectivo >= total ? ()=> Navigator.pop(context, efectivo) : null, child: const Text('Cobrar e imprimir ticket')),
    ]);
  }
}

// ===================== CORTES SCREEN =====================
class CortesScreen extends StatelessWidget {
  final Repo repo;
  const CortesScreen({super.key, required this.repo});

  @override
  Widget build(BuildContext context) {
    final abierto = repo.corteAbierto;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cortes'),
        actions: [
          if (abierto != null)
            IconButton(
              tooltip: 'Cerrar corte y generar PDF',
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: () async {
                await _exportarPdfCorte(context, repo, abierto.id);
                await repo.cerrarCorte();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Corte cerrado y PDF generado')),
                  );
                }
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (abierto != null) _panelCorteActual(context, repo, abierto) else
            Card(
              child: ListTile(
                leading: const Icon(Icons.lock_open),
                title: const Text('No hay corte abierto'),
                subtitle: const Text('Abre un corte para comenzar a registrar ventas por turno'),
                trailing: FilledButton(
                  onPressed: () async { await repo.abrirCorte(); },
                  child: const Text('Abrir corte'),
                ),
              ),
            ),
          const SizedBox(height: 16),
          const Text('Historial de cortes', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...repo.cortes.map((c) => Card(
            child: ListTile(
              leading: Icon(c.abierto ? Icons.play_circle : Icons.stop_circle, color: c.abierto ? Colors.green : null),
              title: Text(c.id),
              subtitle: Text('${c.inicio.toString().substring(0,16)}  →  ${c.fin?.toString().substring(0,16) ?? "(abierto)"}'),
              trailing: Wrap(spacing: 8, children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.visibility),
                  label: const Text('Ver ventas'),
                  onPressed: () => _verVentasDeCorte(context, repo, c.id),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('PDF'),
                  onPressed: () => _exportarPdfCorte(context, repo, c.id),
                ),
              ]),
            ),
          )),
        ],
      ),
    );
  }

  Widget _panelCorteActual(BuildContext context, Repo repo, Corte c) {
    final vs = repo.ventasDeCorte(c.id);
    final total = vs.fold<double>(0, (a, v) => a + v.total);
    final items = vs.fold<int>(0, (a, v) => a + v.lineas.fold(0, (x, l) => x + l.cantidad.toInt()));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Corte abierto', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _kpi('Inicio', c.inicio.toString().substring(0,16)),
              _kpi('Ventas', '${vs.length}'),
              _kpi('Artículos', '$items'),
              _kpi('Total', '\$${total.toStringAsFixed(2)}'),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              icon: const Icon(Icons.lock),
              label: const Text('Cerrar corte'),
              onPressed: () async {
                await repo.cerrarCorte();
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ),
        ]),
      ),
    );
  }

  void _verVentasDeCorte(BuildContext context, Repo repo, String corteId) {
    final vs = repo.ventasDeCorte(corteId);
    showModalBottomSheet(
      context: context, showDragHandle: true,
      builder: (_) => ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: vs.length,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (_, i) {
          final v = vs[i];
          return ListTile(
            title: Text('${v.id} — \$${v.total.toStringAsFixed(2)}'),
            subtitle: Text(v.fecha.toString().substring(0,16)),
          );
        },
      ),
    );
  }

  Future<void> _exportarPdfCorte(BuildContext context, Repo repo, String corteId) async {
    final vs = repo.ventasDeCorte(corteId);
    final total = vs.fold<double>(0, (a, v) => a + v.total);
    final items = vs.fold<int>(0, (a, v) => a + v.lineas.fold(0, (x, l) => x + l.cantidad.toInt()));
    final doc = pw.Document();

    // Top productos del corte
    final Map<String, double> porProducto = {};
    for (final v in vs) {
      for (final l in v.lineas) {
        porProducto[l.producto.nombre] = (porProducto[l.producto.nombre] ?? 0) + l.cantidad;
      }
    }
    final top = porProducto.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top5 = top.take(5).toList();

    doc.addPage(pw.MultiPage(
      pageFormat: pwlib.PdfPageFormat.a4,
      build: (ctx) => [
        pw.Header(level: 0, child: pw.Text('Corte de Caja — $corteId', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))),
        pw.Table(
          border: pw.TableBorder.all(width: 0.2),
          columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(2)},
          children: [
            pw.TableRow(children: [pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Ventas')), pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('${vs.length}'))]),
            pw.TableRow(children: [pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Artículos vendidos')), pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('$items'))]),
            pw.TableRow(children: [pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Total')), pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('\$${total.toStringAsFixed(2)}'))]),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Text('Top 5 productos', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(width: 0.2),
          columnWidths: const {0: pw.FlexColumnWidth(6), 1: pw.FlexColumnWidth(2)},
          children: [
            pw.TableRow(children: [
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Producto', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Cantidad', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
            ]),
            ...top5.map((e) => pw.TableRow(children: [
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(e.key)),
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(e.value.toStringAsFixed(0))),
            ])),
          ],
        ),
      ],
    ));
    await Printing.layoutPdf(onLayout: (format) async => doc.save());
  }

  Widget _kpi(String t, String v) => SizedBox(
    width: 220,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t, style: const TextStyle(color: Colors.black54)),
      const SizedBox(height: 4),
      Text(v, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    ]),
  );
}
