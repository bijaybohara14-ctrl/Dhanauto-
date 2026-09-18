import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

const String mapsApiKey = String.fromEnvironment(
  'MAPS_API_KEY',
  defaultValue: '',
);

const LatLng defaultCenter = LatLng(28.7010, 80.5890);

void main() {
  runApp(const DhanautoApp());
}

class DhanautoApp extends StatelessWidget {
  const DhanautoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Dhanauto',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.red,
        ),
        useMaterial3: true,
      ),
      home: const BookingPage(),
    );
  }
}

class BookingPage extends StatefulWidget {
  const BookingPage({super.key});

  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {
  GoogleMapController? mapController;

  final pickupController = TextEditingController();
  final destinationController = TextEditingController();

  Timer? searchTimer;

  LatLng? pickupPosition;
  LatLng? destinationPosition;

  List<Map<String, dynamic>> suggestions = [];

  bool searchingPickup = false;

  Set<Marker> get markers {
    final result = <Marker>{};

    if (pickupPosition != null) {
      result.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: pickupPosition!,
          draggable: true,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: const InfoWindow(
            title: 'Pickup',
          ),
          onDragEnd: (newPosition) {
            setState(() {
              pickupPosition = newPosition;
              pickupController.text =
                  'Map location (${newPosition.latitude.toStringAsFixed(5)}, '
                  '${newPosition.longitude.toStringAsFixed(5)})';
            });
          },
        ),
      );
    }

    if (destinationPosition != null) {
      result.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: destinationPosition!,
          draggable: true,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueRed,
          ),
          infoWindow: const InfoWindow(
            title: 'Destination',
          ),
          onDragEnd: (newPosition) {
            setState(() {
              destinationPosition = newPosition;
              destinationController.text =
                  'Map location (${newPosition.latitude.toStringAsFixed(5)}, '
                  '${newPosition.longitude.toStringAsFixed(5)})';
            });
          },
        ),
      );
    }

    return result;
  }

  @override
  void initState() {
    super.initState();
    getCurrentLocation();
  }

  Future<void> getCurrentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        showMessage(
          'Phone ko Location/GPS ON गर्नुहोस्।',
        );
        return;
      }

      LocationPermission permission =
          await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission =
            await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        showMessage(
          'Location permission दिनुहोस्।',
        );
        return;
      }

      final position =
          await Geolocator.getCurrentPosition(
        desiredAccuracy:
            LocationAccuracy.high,
      );

      final point = LatLng(
        position.latitude,
        position.longitude,
      );

      if (!mounted) return;

      setState(() {
        pickupPosition = point;
        pickupController.text =
            'Current location';
      });

      mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          point,
          15,
        ),
      );
    } catch (e) {
      debugPrint(
        'Location error: $e',
      );
    }
  }

  void startPickupMapSelection() {
    setState(() {
      searchingPickup = true;
      suggestions = [];
    });

    showMessage(
      'अब map मा tap गरेर Pickup छान्नुहोस्।',
    );
  }

  void startDestinationMapSelection() {
    setState(() {
      searchingPickup = false;
      suggestions = [];
    });

    showMessage(
      'अब map मा tap गरेर Destination छान्नुहोस्।',
    );
  }

  void onSearchChanged(String value) {
    searchTimer?.cancel();

    if (value.trim().length < 2) {
      setState(() {
        suggestions = [];
      });
      return;
    }

    searchTimer = Timer(
      const Duration(milliseconds: 400),
      () {
        searchPlaces(value.trim());
      },
    );
  }

  Future<void> searchPlaces(String input) async {
    if (mapsApiKey.isEmpty) {
      debugPrint(
        'MAPS_API_KEY missing',
      );
      return;
    }

    try {
      final response = await http.post(
        Uri.parse(
          'https://places.googleapis.com/v1/places:autocomplete',
        ),
        headers: {
          'Content-Type':
              'application/json',
          'X-Goog-Api-Key':
              mapsApiKey,
          'X-Goog-FieldMask':
              'suggestions.placePrediction.placeId,'
              'suggestions.placePrediction.text,'
              'suggestions.placePrediction.structuredFormat',
        },
        body: jsonEncode({
          'input': input,
          'languageCode': 'en',
        }),
      );

      if (response.statusCode != 200) {
        debugPrint(
          'Places error ${response.statusCode}: '
          '${response.body}',
        );
        return;
      }

      final data =
          jsonDecode(response.body);

      final raw =
          data['suggestions'] ?? [];

      final results =
          <Map<String, dynamic>>[];

      for (final item in raw) {
        final prediction =
            item['placePrediction'];

        if (prediction != null) {
          final text =
              prediction['text']?['text'] ??
                  '';

          if (text.toString().isNotEmpty) {
            results.add({
              'placeId':
                  prediction['placeId'],
              'text': text,
            });
          }
        }
      }

      if (!mounted) return;

      setState(() {
        suggestions = results;
      });
    } catch (e) {
      debugPrint(
        'Search error: $e',
      );
    }
  }

  Future<void> selectPlace(
    Map<String, dynamic> place,
  ) async {
    final placeId =
        place['placeId'];

    if (placeId == null ||
        mapsApiKey.isEmpty) {
      return;
    }

    try {
      final response = await http.get(
        Uri.parse(
          'https://places.googleapis.com/v1/places/$placeId',
        ),
        headers: {
          'X-Goog-Api-Key':
              mapsApiKey,
          'X-Goog-FieldMask':
              'location,displayName,formattedAddress',
        },
      );

      if (response.statusCode != 200) {
        debugPrint(
          'Place details error: '
          '${response.statusCode} '
          '${response.body}',
        );
        return;
      }

      final data =
          jsonDecode(response.body);

      final location =
          data['location'];

      if (location == null) {
        return;
      }

      final point = LatLng(
        (location['latitude'] as num)
            .toDouble(),
        (location['longitude'] as num)
            .toDouble(),
      );

      final name =
          data['displayName']?['text'] ??
          data['formattedAddress'] ??
          place['text'];

      if (!mounted) return;

      setState(() {
        if (searchingPickup) {
          pickupPosition = point;
          pickupController.text =
              name.toString();
        } else {
          destinationPosition = point;
          destinationController.text =
              name.toString();
        }

        suggestions = [];
      });

      mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          point,
          15,
        ),
      );
    } catch (e) {
      debugPrint(
        'Place details error: $e',
      );
    }
  }

  void onMapTap(LatLng point) {
    setState(() {
      if (searchingPickup) {
        pickupPosition = point;

        pickupController.text =
            'Map location (${point.latitude.toStringAsFixed(5)}, '
            '${point.longitude.toStringAsFixed(5)})';
      } else {
        destinationPosition = point;

        destinationController.text =
            'Map location (${point.latitude.toStringAsFixed(5)}, '
            '${point.longitude.toStringAsFixed(5)})';
      }

      suggestions = [];
    });

    showMessage(
      searchingPickup
          ? 'Pickup location राखियो। Marker सार्न पनि मिल्छ।'
          : 'Destination राखियो। Marker सार्न पनि मिल्छ।',
    );
  }

  void clearPickup() {
    setState(() {
      pickupPosition = null;
      pickupController.clear();
    });
  }

  void clearDestination() {
    setState(() {
      destinationPosition = null;
      destinationController.clear();
      suggestions = [];
    });
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  void bookRide() {
    if (pickupPosition == null) {
      showMessage(
        'Pickup location छान्नुहोस्।',
      );
      return;
    }

    if (destinationPosition == null) {
      showMessage(
        'Destination छान्नुहोस्।',
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.all(20),
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                const Text(
                  'Dhanauto भेटियो',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                const SizedBox(
                  height: 12,
                ),

                const ListTile(
                  leading:
                      CircleAvatar(
                    child: Icon(
                      Icons
                          .electric_rickshaw,
                    ),
                  ),
                  title: Text(
                    'Dhanauto E-Rickshaw',
                  ),
                  subtitle: Text(
                    'Driver खोजिँदैछ',
                  ),
                  trailing: Text(
                    'Rs. 120',
                    style: TextStyle(
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),

                const SizedBox(
                  height: 12,
                ),

                SizedBox(
                  width:
                      double.infinity,
                  child:
                      FilledButton(
                    onPressed: () {
                      Navigator.pop(
                        context,
                      );

                      showMessage(
                        'Ride request पठाइयो!',
                      );
                    },
                    child: const Text(
                      'Confirm Ride',
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget buildSearchSuggestions() {
    if (suggestions.isEmpty) {
      return const SizedBox();
    }

    return Container(
      constraints:
          const BoxConstraints(
        maxHeight: 240,
      ),
      margin:
          const EdgeInsets.only(
        top: 5,
      ),
      decoration:
          BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(
          10,
        ),
        boxShadow: const [
          BoxShadow(
            blurRadius: 8,
            color: Colors.black26,
          ),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount:
            suggestions.length,
        separatorBuilder:
            (_, __) =>
                const Divider(
          height: 1,
        ),
        itemBuilder:
            (context, index) {
          final place =
              suggestions[index];

          return ListTile(
            leading:
                const Icon(
              Icons.location_on,
              color: Colors.red,
            ),
            title: Text(
              place['text'] ??
                  '',
            ),
            onTap: () {
              selectPlace(
                place,
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Dhanauto',
          style: TextStyle(
            fontWeight:
                FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            onPressed:
                getCurrentLocation,
            icon:
                const Icon(
              Icons.my_location,
            ),
          ),
        ],
      ),

      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition:
                const CameraPosition(
              target:
                  defaultCenter,
              zoom: 9,
            ),

            myLocationEnabled:
                true,

            myLocationButtonEnabled:
                false,

            zoomControlsEnabled:
                false,

            markers: markers,

            onMapCreated:
                (controller) {
              mapController =
                  controller;

              if (pickupPosition !=
                  null) {
                controller
                    .animateCamera(
                  CameraUpdate
                      .newLatLngZoom(
                    pickupPosition!,
                    15,
                  ),
                );
              }
            },

            onTap:
                onMapTap,
          ),

          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Card(
              child: Padding(
                padding:
                    const EdgeInsets
                        .all(12),
                child: Row(
                  children: [
                    const Icon(
                      Icons
                          .info_outline,
                    ),
                    const SizedBox(
                      width: 8,
                    ),
                    Expanded(
                      child: Text(
                        searchingPickup
                            ? 'Pickup छान्न map मा tap गर्नुहोस्'
                            : 'Destination छान्न map मा tap गर्नुहोस्',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            left: 16,
            right: 16,
            bottom: 18,
            child: Card(
              elevation: 8,
              child: Padding(
                padding:
                    const EdgeInsets
                        .all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child:
                              TextField(
                            controller:
                                pickupController,
                            readOnly: true,
                            decoration:
                                InputDecoration(
                              prefixIcon:
                                  const Icon(
                                Icons
                                    .my_location,
                              ),
                              labelText:
                                  'Pickup location',
                              border:
                                  const OutlineInputBorder(),
                              suffixIcon:
                                  pickupController
                                          .text
                                          .isNotEmpty
                                      ? IconButton(
                                          onPressed:
                                              clearPickup,
                                          icon:
                                              const Icon(
                                            Icons.clear,
                                          ),
                                        )
                                      : null,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip:
                              'Choose pickup on map',
                          onPressed:
                              startPickupMapSelection,
                          icon:
                              const Icon(
                            Icons.map,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(
                      height: 10,
                    ),

                    TextField(
                      controller:
                          destinationController,
                      onChanged:
                          onSearchChanged,
                      onTap: () {
                        setState(() {
                          searchingPickup =
                              false;
                        });
                      },
                      decoration:
                          InputDecoration(
                        prefixIcon:
                            const Icon(
                          Icons
                              .location_on,
                        ),
                        labelText:
                            'Where to?',
                        hintText:
                            'Type location name',
                        border:
                            const OutlineInputBorder(),
                        suffixIcon:
                            destinationController
                                    .text
                                    .isNotEmpty
                                ? IconButton(
                                    onPressed:
                                        clearDestination,
                                    icon:
                                        const Icon(
                                      Icons.clear,
                                    ),
                                  )
                                : null,
                      ),
                    ),

                    buildSearchSuggestions(),

                    const SizedBox(
                      height: 8,
                    ),

                    SizedBox(
                      width:
                          double.infinity,
                      child:
                          OutlinedButton
                              .icon(
                        onPressed:
                            startDestinationMapSelection,
                        icon:
                            const Icon(
                          Icons.map,
                        ),
                        label:
              
