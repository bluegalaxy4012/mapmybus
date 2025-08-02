import 'package:flutter/material.dart';
import 'package:mapmybus/providers/city_provider.dart';
import 'package:mapmybus/utils.dart';
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

            const Text(
              "Momentan doar Cluj-Napoca este suportat complet.",
              style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
            ),

            const SizedBox(height: 40),

            const Text(
              "Disclaimer: Aproximarile de timp nu vor fi mereu complet corecte.",
              style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
