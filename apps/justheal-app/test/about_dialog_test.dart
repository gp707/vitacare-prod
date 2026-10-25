import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

import 'package:nursenow_app/about/about_dialog.dart';

Future<PackageInfo> _info() async => PackageInfo(
      appName: 'JustHeal',
      packageName: 'in.vitacasahealth.justheal',
      version: '1.0.0',
      buildNumber: '7',
    );

Future<void> _pump(WidgetTester tester, {required List<Uri> launched, VoidCallback? onTripleTap}) async {
  VitaBrandActions.onLogoTap = (context) => showAboutBuildDialog(
        context,
        loadPackageInfo: _info,
        launcher: (uri) async {
          launched.add(uri);
          return true;
        },
      );
  addTearDown(() => VitaBrandActions.onLogoTap = null);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(appBar: AppBar(title: VitaAppBarTitle('Home', onTripleTap: onTripleTap))),
  ));
}

void main() {
  testWidgets('a single tap on the logo shows version, company and website', (tester) async {
    await _pump(tester, launched: []);

    await tester.tap(find.byKey(const ValueKey('vitaAppBarBrandIconTap')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Version 1.0.0 (build 7)'), findsOneWidget);
    expect(find.text('VitaCasaHealth Services'), findsOneWidget);
    expect(find.text('vitacasahealth.in'), findsOneWidget);
  });

  testWidgets('tapping the website opens https://vitacasahealth.in', (tester) async {
    final launched = <Uri>[];
    await _pump(tester, launched: launched);

    await tester.tap(find.byKey(const ValueKey('vitaAppBarBrandIconTap')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('aboutWebsiteLink')));

    expect(launched, [Uri.parse('https://vitacasahealth.in')]);
  });

  testWidgets('triple tap still fires the logout gesture and does not open About', (tester) async {
    var tripleTaps = 0;
    await _pump(tester, launched: [], onTripleTap: () => tripleTaps++);

    final logo = find.byKey(const ValueKey('vitaAppBarBrandIconTap'));
    for (var i = 0; i < 3; i++) {
      await tester.tap(logo);
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(tripleTaps, 1);
    expect(find.text('VitaCasaHealth Services'), findsNothing);
  });

  testWidgets('a login-screen style logo wrapped in VitaLogoTap opens About immediately', (tester) async {
    VitaBrandActions.onLogoTap = (context) => showAboutBuildDialog(context, loadPackageInfo: _info);
    addTearDown(() => VitaBrandActions.onLogoTap = null);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: VitaLogoTap(child: SizedBox(width: 60, height: 60)))));

    await tester.tap(find.byKey(const ValueKey('vitaLogoTap')));
    await tester.pumpAndSettle();

    expect(find.text('Version 1.0.0 (build 7)'), findsOneWidget);
  });
}
