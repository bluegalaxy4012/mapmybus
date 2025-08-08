import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:mapmybus/providers/city_provider.dart';
import 'package:mapmybus/widgets/home_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});
  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final PageController _controller = PageController();

  Future<void> _continueToApp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seen_welcome', true); // tutorial

    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const MyHomePage()));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cityProvider = Provider.of<CityProvider>(context);

    return Scaffold(
      body: Stack(
        children: [
          PageView(
            controller: _controller,
            scrollDirection: Axis.vertical,
            physics: const PageScrollPhysics(),

            dragStartBehavior: DragStartBehavior.down,
            scrollBehavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
              },
            ),

            children: [
              Center(child: Image.asset('assets/map_my_bus.png')),

              Center(child: Image.asset('assets/map_my_bus_tutorial.png')),

              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),

                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Column(
                        children: [
                          const Text(
                            "Bine ai venit pe",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          const Text(
                            "Map My Bus!",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),

                      const Text(
                        "Selecteaza orasul:",
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const Text(
                        "(Se poate schimba in setari ulterior)",
                        style: TextStyle(fontSize: 11, color: Colors.grey),
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
                          DropdownMenuItem(
                            value: "Chisinau",
                            child: Text("Chisinau"),
                          ),
                          DropdownMenuItem(
                            value: "Botosani",
                            child: Text("Botosani"),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) cityProvider.setCity(v);
                        },
                      ),

                      const Spacer(),
                      Column(
                        children: [
                          const Text(
                            "Disclaimere:",
                            style: TextStyle(color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),

                          const Text(
                            "Uneori datele de pe harta pot sa nu corespunda cu realitatea.",
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Colors.grey,
                            ),
                            textAlign: TextAlign.center,
                          ),

                          const Text(
                            "Aproximarile de timp nu vor fi mereu complet corecte.",
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Colors.grey,
                            ),
                            textAlign: TextAlign.center,
                          ),

                          const Text(
                            "La rutele ciclice, functionalitatile de estimare pot esua.",
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Colors.grey,
                            ),
                            textAlign: TextAlign.center,
                          ),

                          const Text(
                            "Pot exista statii diferite cu acelasi nume. Alege cu atentie.",
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Colors.grey,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),

                      const SizedBox(height: 48),

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
                        child: const Text(
                          "Start",
                          style: TextStyle(fontStyle: FontStyle.italic),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          Positioned(
            right: 16,
            top: MediaQuery.of(context).size.height * 0.4,

            child: SmoothPageIndicator(
              controller: _controller,
              count: 3,
              axisDirection: Axis.vertical,

              effect: const WormEffect(
                dotColor: Colors.grey,
                activeDotColor: Colors.orangeAccent,
                dotHeight: 12,
                dotWidth: 12,
                spacing: 16,
              ),

              onDotClicked: (idx) => _controller.animateToPage(
                idx,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
