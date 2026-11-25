import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/compare_controller.dart';
import 'theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});

  final CompareController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _port;
  late final TextEditingController _website;

  @override
  void initState() {
    super.initState();
    _port = TextEditingController(text: widget.controller.tallyPort);
    _website = TextEditingController(text: widget.controller.website);
  }

  @override
  void dispose() {
    _port.dispose();
    _website.dispose();
    super.dispose();
  }

  void _pushFields() {
    widget.controller.setConnectionFields(_port.text, _website.text);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final practice = controller.practiceSite;
        return Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Settings',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: tsInk,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Choose the Tally port and the Tracksheet website. Compare still only reads until saving is turned on for the Tracksheet.',
                    style: TextStyle(color: tsMuted, height: 1.4),
                  ),
                  const SizedBox(height: 22),
                  const _FieldLabel('Tally port'),
                  TextField(
                    controller: _port,
                    enabled: !controller.checkingConnection,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: _decoration(hint: '9000'),
                    onChanged: (_) => _pushFields(),
                  ),
                  const SizedBox(height: 16),
                  const _FieldLabel('Website'),
                  TextField(
                    controller: _website,
                    enabled: !controller.checkingConnection,
                    decoration: _decoration(
                      hint: 'http://127.0.0.1:8765',
                    ),
                    onChanged: (_) => _pushFields(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    practice
                        ? 'This address is the Tracksheet on this computer.'
                        : 'Saving stays off. Write works only for the Tracksheet on this computer (http://127.0.0.1:8765).',
                    style: const TextStyle(fontSize: 12, color: tsMuted),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: controller.checkingConnection
                        ? null
                        : () {
                            _pushFields();
                            controller.checkConnection();
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: tsGreen,
                      foregroundColor: tsWhite,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: Icon(
                      controller.checkingConnection
                          ? Icons.hourglass_top
                          : Icons.lan_outlined,
                    ),
                    label: Text(controller.checkingConnection ? 'Checking…' : 'Check connection'),
                  ),
                  if (controller.connectionNote.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      controller.connectionNote,
                      style: const TextStyle(color: tsInk, height: 1.4),
                    ),
                  ],
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: tsWhite,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: tsLine),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Allow saving on the Tracksheet',
                                style: TextStyle(fontWeight: FontWeight.w600, color: tsInk),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                practice
                                    ? 'When this is on, Write can fill Bill #, Labour, Spares, Total, VAS, and Items on the Tracksheet.'
                                    : 'Turn this on only for the Tracksheet at http://127.0.0.1:8765. The live site is never saved to.',
                                style: const TextStyle(fontSize: 12, color: tsMuted, height: 1.35),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: practice && controller.allowPracticeSave,
                          activeThumbColor: tsGreen,
                          onChanged: practice && !controller.checkingConnection
                              ? controller.setAllowPracticeSave
                              : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: tsMuted, fontWeight: FontWeight.w600),
      ),
    );
  }
}

InputDecoration _decoration({required String hint}) {
  return InputDecoration(
    hintText: hint,
    isDense: true,
    filled: true,
    fillColor: tsWhite,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
    border: const OutlineInputBorder(
      borderSide: BorderSide(color: tsLine),
      borderRadius: BorderRadius.all(Radius.circular(8)),
    ),
    enabledBorder: const OutlineInputBorder(
      borderSide: BorderSide(color: tsLine),
      borderRadius: BorderRadius.all(Radius.circular(8)),
    ),
  );
}
