import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../core/db/database.dart' as db;
import '../../core/env.dart';

/// Muestra la finca y su límite (polígono) sobre un mapa Mapbox.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.farm});
  final db.Farm farm;
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  @override
  Widget build(BuildContext context) {
    if (Env.mapboxToken.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.farm.name)),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Falta el token de Mapbox.\nEjecuta con --dart-define=MAPBOX_TOKEN=pk.xxxx',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final center = Point(
      coordinates: Position(widget.farm.lng ?? -75.595, widget.farm.lat ?? 6.205),
    );

    return Scaffold(
      appBar: AppBar(title: Text(widget.farm.name)),
      body: MapWidget(
        cameraOptions: CameraOptions(center: center, zoom: 13),
        styleUri: MapboxStyles.SATELLITE_STREETS,
        onMapCreated: _onMapCreated,
      ),
    );
  }

  Future<void> _onMapCreated(MapboxMap map) async {
    final ring = _parseBoundary(widget.farm.boundaryJson);
    if (ring.isEmpty) return;
    final manager = await map.annotations.createPolygonAnnotationManager();
    await manager.create(PolygonAnnotationOptions(
      geometry: Polygon(coordinates: [ring]),
      fillColor: Colors.green.toARGB32(),
      fillOpacity: 0.35,
      fillOutlineColor: Colors.green.shade900.toARGB32(),
    ));
  }

  List<Position> _parseBoundary(String? json) {
    if (json == null) return [];
    try {
      final list = jsonDecode(json) as List;
      return list
          .map((p) => Position((p[0] as num).toDouble(), (p[1] as num).toDouble()))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
