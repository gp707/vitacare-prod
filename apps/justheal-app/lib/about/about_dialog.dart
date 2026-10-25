import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

const String companyName = 'VitaCasaHealth Services';
const String companyWebsiteLabel = 'vitacasahealth.in';
final Uri companyWebsiteUri = Uri.parse('https://vitacasahealth.in');

/// Opens the website — swappable so widget tests capture the URI instead of
/// leaving the app (same convention as the registration screens' terms link).
typedef WebsiteLauncher = Future<bool> Function(Uri uri);

Future<bool> _defaultLauncher(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

/// Registers the About dialog as the single-tap action of every brand logo
/// (see [VitaBrandActions]). Called once from main().
void registerAboutOnLogoTap() {
  VitaBrandActions.onLogoTap = (context) => showAboutBuildDialog(context);
}

/// Shows the installed build's version and who makes the app.
Future<void> showAboutBuildDialog(
  BuildContext context, {
  Future<PackageInfo> Function()? loadPackageInfo,
  WebsiteLauncher launcher = _defaultLauncher,
}) {
  return showDialog<void>(
    context: context,
    routeSettings: const RouteSettings(name: '/about'),
    builder: (_) => _AboutBuildDialog(loadPackageInfo: loadPackageInfo ?? PackageInfo.fromPlatform, launcher: launcher),
  );
}

class _AboutBuildDialog extends StatelessWidget {
  final Future<PackageInfo> Function() loadPackageInfo;
  final WebsiteLauncher launcher;

  const _AboutBuildDialog({required this.loadPackageInfo, required this.launcher});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('JustHeal'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FutureBuilder<PackageInfo>(
            future: loadPackageInfo(),
            builder: (context, snapshot) {
              final info = snapshot.data;
              final text = info == null
                  ? (snapshot.hasError ? 'Version unavailable' : 'Version …')
                  : 'Version ${info.version} (build ${info.buildNumber})';
              return Text(text, key: const Key('aboutVersion'));
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(companyName),
          const SizedBox(height: AppSpacing.xs),
          InkWell(
            key: const Key('aboutWebsiteLink'),
            onTap: () => launcher(companyWebsiteUri).catchError((_) => false),
            child: const Text(
              companyWebsiteLabel,
              style: TextStyle(color: AppColors.primaryDark, decoration: TextDecoration.underline),
            ),
          ),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
    );
  }
}
