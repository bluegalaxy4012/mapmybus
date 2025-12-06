import 'package:flutter/material.dart';
import 'package:mapmybus/providers/city_provider.dart';
import 'package:mapmybus/core/utils.dart';
import 'package:provider/provider.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cityProvider = Provider.of<CityProvider>(context);
    final currentCity = cityProvider.city;

    return Scaffold(
      appBar: AppBar(title: const Text("Setari")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SizedBox(),

            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Alege orasul:"),

                DropdownButton<String>(
                  value: currentCity,

                  dropdownColor: Theme.of(context).colorScheme.surface,
                  focusColor: Colors.transparent,

                  underline: const SizedBox(),

                  items: Constants.availableCityNames.map((city) {
                    return DropdownMenuItem(value: city, child: Text(city));
                  }).toList(),

                  onChanged: (newCity) {
                    if (newCity != null) {
                      cityProvider.setCity(newCity);
                    }
                  },
                ),
              ],
            ),

            Padding(
              padding: const EdgeInsets.all(16),

              child: ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,

                    builder: (ctx) => Dialog(
                      child: InteractiveViewer(
                        child: Image.asset(
                          'assets/map_my_bus_tutorial.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  );
                },

                child: const Text("Explicatii"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
