import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:roxum/l10n/app_localizations.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:roxum/bloc/ui_bloc/ui_bloc.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final color = context.read<AppThemeBloc>().state.appTheme.selectScreenCardTextColor;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.aboutRoxum),
        titleTextStyle: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 20
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(
                radius: 40,
                backgroundImage: AssetImage('assets/icons/app-icon.png'),
              ),
              const SizedBox(height: 24),
              Text(
                l10n.appTitle,
                style: TextStyle(
                  color: color,
                  fontSize: 28,
                  fontWeight: FontWeight.bold
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.versionLabel('2.5.0'),
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              Text(
                l10n.aboutDescription,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 15
                ),
              ),
              const SizedBox(height: 24),
              Text(
                l10n.aboutDeveloper,
                style: TextStyle(
                  color: color,
                  fontSize: 19,
                ),
              ),
              const SizedBox(height: 20),
                Text(l10n.developerIntro,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 15
                  ),
                ),
                DefaultTextStyle(
                  style: TextStyle(
                    color: color,
                    fontSize: 13.5
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 18),
                      Text(l10n.getInTouch),
                      Row(
                        children: [
                          IconButton(
                            onPressed: () async => await launchUrl(Uri.parse("mailto:athulas2005@gmail.com")),
                            icon: Icon(
                              Icons.email,
                              size: 30,
                            ),
                            color: color,
                          ),
                          IconButton(
                            onPressed: () async => await launchUrl(Uri.parse("https://www.linkedin.com/in/athul-a-s-43ab54272?utm_source=share&utm_campaign=share_via&utm_content=profile&utm_medium=android_app")),
                            icon: FaIcon(FontAwesomeIcons.linkedin, size: 25.2),
                            color: Colors.blue,
                          ),
                          IconButton(
                            onPressed: () async => await launchUrl(Uri.parse("https://github.com/heckmon")),
                            icon: FaIcon(FontAwesomeIcons.github),
                            color: color,
                          )
                        ],
                      )
                    ],
                  )
                )
            ],
          ),
        ),
      ),
    );
  }
}