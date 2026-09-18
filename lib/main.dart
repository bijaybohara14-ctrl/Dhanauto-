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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
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

  final pickup = TextEditingController();
  final destination = TextEditingController();

  Timer? searchTimer;

  Position? currentPosition;
  LatLng? destinationPosition;

  List<Map<String, dynamic>> suggestions = [];

  static const LatLng defaultCenter = LatLng(27.7172, 85.3240);

  Set<Marker> get markers {
    final result = <Marker>{};

    if (currentPosition != null) {
      result.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: LatLng(
            currentPosition!.latitude,
            currentPosition!.longitude,
          ),
          infoWindow: const InfoWindow(title: 'Pickup location'),
        ),
      );
    }

    if (destinationPosition != null) {
      result.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: destinationPosition!,
          infoWindow: const InfoWindow(title: 'Destination'),
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
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        return;
      }

      LocationPermission permission =
          await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (!mounted) return;

      setState(() {
        currentPosition = position;
        pickup.text =
            'Current location (${position.latitude.toStringAsFixed(5)}, '
            '${position.longitude.toStringAsFixed(5)})';
      });

      mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(position.latitude, position.longitude),
          15,
        ),
      );
    } catch (e) {
      debugPrint('Location error: $e');
    }
  }

  void onDestinationChanged(String value) {
    searchTimer?.cancel();

    if (value.trim().length < 2) {
      setState(() {
        suggestions = [];
      });
      return;
    }

    searchTimer = Timer(
      const Duration(milliseconds: 500),
      () {
        searchPlaces(value.trim());
      },
    );
  }

  Future<void> searchPlaces(String input) async {
    if (mapsApiKey.isEmpty) {
      debugPrint('MAPS_API_KEY is missing');
      return;
    }

    try {
      final response = await http.post(
        Uri.parse(
          'https://places.googleapis.com/v1/places:autocomplete',
        ),
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': mapsApiKey,
          'X-Goog-FieldMask':
              'suggestions.placePrediction.placeId,'
              'suggestions.placePrediction.text',
        },
        body: jsonEncode({
          'input': input,
          'languageCode': 'en',
        }),
      );

      if (response.statusCode != 200) {
        debugPrint(
          'Places error ${response.statusCode}: ${response.body}',
        );
        return;
      }

      final data = jsonDecode(response.body);

      final List<dynamic> rawSuggestions =
          data['suggestions'] ?? [];

      final results = <Map<String, dynamic>>[];

      for (final item in rawSuggestions) {
        final prediction = item['placePrediction'];

        if (prediction != null) {
          results.add({
            'placeId': prediction['placeId'],
            'text': prediction['text']?['text'] ?? '',
          });
        }
      }

      if (!mounted) return;

      setState(() {
        suggestions = results;
      });
    } catch (e) {
      debugPrint('Search error: $e');
    }
  }

  Future<void> selectPlace(Map<String, dynamic> place) async {
    final placeId = place['placeId'];

    if (placeId == null || mapsApiKey.isEmpty) {
      return;
    }

    try {
      final url = Uri.parse(
        'https://places.googleapis.com/v1/places/$placeId',
      );

      final response = await http.get(
        url,
        headers: {
          'X-Goog-Api-Key': mapsApiKey,
          'X-Goog-FieldMask':
              'location,displayName,formattedAddress',
        },
      );

      if (response.statusCode != 200) {
        debugPrint(
          'Place details error ${response.statusCode}: '
          '${response.body}',
        );
        return;
      }

      final data = jsonDecode(response.body);

      final location = data['location'];

      if (location == null) return;

      final lat = (location['latitude'] as num).toDouble();
      final lng = (location['longitude'] as num).toDouble();

      final selectedText =
          data['displayName']?['text'] ??
          data['formattedAddress'] ??
          place['text'];

      if (!mounted) return;

      setState(() {
        destination.text = selectedText;
        destination.selection = TextSelection.fromPosition(
          TextPosition(offset: destination.text.length),
        );

        destinationPosition = LatLng(lat, lng);
        suggestions = [];
      });

      mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(lat, lng),
          15,
        ),
      );
    } catch (e) {
      debugPrint('Place details error: $e');
    }
  }

  void bookRide() {
    if (pickup.text.trim().isEmpty ||
        destination.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pickup र destination भर्नुहोस्'),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Dhanauto भेटियो',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const ListTile(
                leading: CircleAvatar(
                  child: Icon(Icons.electric_rickshaw),
                ),
                title: Text('Dhanauto E-Rickshaw'),
                subtitle: Text(
                  'Driver खोजिँदैछ • ETA लगभग 3–5 min',
                ),
                trailing: Text(
                  'Rs. 120',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(context);

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Ride request पठाइयो!',
                        ),
                      ),
                    );
                  },
                  child: const Text('Confirm Ride'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    searchTimer?.cancel();
    pickup.dispose();
    destination.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Dhanauto',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            onPressed: getCurrentLocation,
            icon: const Icon(Icons.my_location),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(
              Icons.notifications_none,
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: defaultCenter,
              zoom: 13,
            ),
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            markers: markers,
            onMapCreated: (controller) {
              mapController = controller;

              if (currentPosition != null) {
                controller.animateCamera(
                  CameraUpdate.newLatLngZoom(
                    LatLng(
                      currentPosition!.latitude,
                      currentPosition!.longitude,
                    ),
                    15,
                  ),
                );
              }
            },
          ),

          Positioned(
            left: 16,
            right: 16,
            bottom: 18,
            child: Card(
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: pickup,
                      readOnly: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(
                          Icons.my_location,
                        ),
                        labelText: 'Pickup location',
                        border: OutlineInputBorder(),
                      ),
                    ),

                    const SizedBox(height: 10),

                    TextField(
                      controller: destination,
                      onChanged: onDestinationChanged,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(
                          Icons.location_on,
                        ),
                        labelText: 'Where to?',
                        border: const OutlineInputBorder(),
                        suffixIcon: destination.text.isNotEmpty
                            ? IconButton(
                                onPressed: () {
                                  destination.clear();
                                  setState(() {
                                    suggestions = [];
                                    destinationPosition = null;
                                  });
                                },
                                icon: const Icon(Icons.clear),
                              )
                            : null,
                      ),
                    ),

                    if (suggestions.isNotEmpty)
                      Container(
                        constraints: const BoxConstraints(
                          maxHeight: 230,
                        ),
                        margin: const EdgeInsets.only(top: 5),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surface,
                          borderRadius:
                              BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.grey.shade300,
                          ),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: suggestions.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final place =
                                suggestions[index];

                            return ListTile(
                              leading: const Icon(
                                Icons.location_on,
                              ),
                              title: Text(
                                place['text'] ?? '',
                              ),
                              onTap: () {
                                selectPlace(place);
                              },
                            );
                          },
                        ),
                      ),

                    const SizedBox(height: 12),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: bookRide,
                        icon: const Icon(Icons.search),
                        label: const Text(
                          'Find Dhanauto',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
