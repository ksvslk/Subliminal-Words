import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:operation_hermes/menu/license_detail_page.dart'; 
import 'package:operation_hermes/oss_licenses.dart'; 

class LicensesDialog extends StatelessWidget {
  const LicensesDialog({super.key});

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final sortedLicenses = List<Package>.from(allDependencies)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("Licenses"),
      ),
      body: ListView.builder(
        physics: const BouncingScrollPhysics(),
        itemCount: sortedLicenses.length,
        itemBuilder: (_, index) {
          final package = sortedLicenses[index];
          final licenseText = package.license;

          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListTile(
                onTap: (licenseText != null && licenseText.isNotEmpty)
                    ? () {
                        Navigator.push(
                          context,
                          CupertinoPageRoute(
                            builder: (_) => LicenseDetailPage(
                              title: _capitalize(package.name),
                              licence: licenseText, 
                            ),
                          ),
                        );
                      }
                    : null,
                title: Text(
                  _capitalize(package.name),
                ),
                subtitle: Text(package.description),
                trailing: (licenseText != null && licenseText.isNotEmpty)
                    ? const Icon(Icons.chevron_right)
                    : null,
              ),
            ),
          );
        },
      ),
    );
  }
}