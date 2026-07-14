import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/db/database.dart' as db;
import '../../core/env.dart';

/// Muestra la finca y su límite (polígono) sobre un mapa MapLibre (tiles MapTiler).
class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.farm});
  final db.Farm farm;
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  MapLibreMapController? _controller;

  @override
  Widget build(BuildContext context) {
    if (Env.maptilerKey.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.farm.name)),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Falta la key de MapTiler.\nEjecuta con --dart-define=MAPTILER_KEY=...',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.farm.name)),
      body: MapLibreMap(
        styleString: 'https://api.maptiler.com/maps/hybrid/style.json?key=${Env.maptilerKey}',
        initialCameraPosition: CameraPosition(
          target: LatLng(widget.farm.lat ?? 6.205, widget.farm.lng ?? -75.595),
          zoom: 13,
        ),
        onMapCreated: (c) => _controller = c,
        onStyleLoadedCallback: _drawBoundary,
      ),
    );
  }

  Future<void> _drawBoundary() async {
    final ring = _parseBoundary(widget.farm.boundaryJson);
    if (ring.isEmpty || _controller == null) return;
    await _controller!.addFill(FillOptions(
      geometry: [ring],
      fillColor: '#22c55e',
      fillOpacity: 0.35,
      fillOutlineColor: '#14532d',
    ));
  }

  List<LatLng> _parseBoundary(String? json) {
    if (json == null) return [];
    try {
      final list = jsonDecode(json) as List;
      // El backend guarda [lng, lat]; LatLng espera (lat, lng).
      return list
          .map((p) => LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
