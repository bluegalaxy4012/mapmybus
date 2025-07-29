import 'package:flutter/material.dart';
import 'package:mapmybus/providers/city_provider.dart';
import 'package:mapmybus/widgets/home_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  Future<void> _continueToApp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seen_welcome', true);

    if (!mounted) return;

    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => MyHomePage()));
  }

  @override
  Widget build(BuildContext context) {
    final cityProvider = Provider.of<CityProvider>(context);

    return Scaffold(
      body: SingleChildScrollView(
        child: Center(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),

              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,

                children: [
                  Image.asset('assets/mapmybus.png', height: 400),

                  const SizedBox(height: 40),

                  const Text(
                    "Bine ai venit la MapMyBus!",
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 16),

                  const Text(
                    "Urmareste transportul public in timp real.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),

                  const SizedBox(height: 60),

                  const Text(
                    "Selecteaza orasul:",
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),

                  const Text(
                    "(Se poate schimba in setari ulterior)",
                    style: TextStyle(fontSize: 10, color: Colors.grey),
                  ),

                  const SizedBox(height: 8),

                  DropdownButton<String>(
                    value: cityProvider.city,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(
                        value: "Cluj-Napoca",
                        child: Text("Cluj-Napoca"),
                      ),
                      DropdownMenuItem(
                        value: "Timisoara",
                        child: Text("Timisoara"),
                      ),
                      DropdownMenuItem(value: "Iasi", child: Text("Iasi")),
                    ],
                    onChanged: (value) {
                      if (value == null) return;

                      cityProvider.setCity(value);
                    },
                  ),

                  // const Spacer(),
                  const SizedBox(height: 130),

                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: 24,
                        horizontal: 48,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),

                    onPressed: _continueToApp,

                    child: const Text("Start"),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
