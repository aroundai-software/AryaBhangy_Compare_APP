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
        if (controller.company.isNotEmpty &&
            controller.voucherTypesCompany != controller.company &&
            !controller.loadingVoucherTypes) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              widget.controller.loadVoucherTypes();
            }
          });
        }
        final saveNote = practice
            ? 'When this is on, Write can fill Bill #, Labour, Spares, Total, VAS, and Items on this website.'
            : controller.liveWebsite
                ? 'Saving stays off until the update token is in the app.'
                : 'Saving stays off for this address.';
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
                    'Choose the Tally port and the Tracksheet website. Compare reads that site. Write saves on that same site when saving is turned on.',
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
                      hint: 'https://example.com',
                    ),
                    onChanged: (_) => _pushFields(),
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
                                saveNote,
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
                  const SizedBox(height: 22),
                  _VoucherTypes(controller: controller),
                  const SizedBox(height: 28),
                  const Text(
                    'Version 1.0.2',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: tsMuted,
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

class _VoucherTypes extends StatelessWidget {
  const _VoucherTypes({required this.controller});

  final CompareController controller;

  Future<void> _open(BuildContext context) async {
    if (controller.company.isEmpty) {
      return;
    }
    controller.loadVoucherTypes();
    await showDialog<void>(
      context: context,
      builder: (context) => _VoucherTypeDialog(controller: controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    final company = controller.company;
    final saved = company.isNotEmpty && controller.voucherTypesByCompany.containsKey(company);
    final savedNames = saved ? controller.voucherTypesByCompany[company]! : const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel('Select voucher types'),
        Material(
          color: tsWhite,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: company.isEmpty ? null : () => _open(context),
            child: InputDecorator(
              decoration: _decoration(hint: ''),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Select voucher types',
                      style: TextStyle(color: company.isEmpty ? tsMuted : tsInk),
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, color: tsMuted),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (company.isEmpty)
          const Text(
            'Open a company in Tally first. The list is for that company only.',
            style: TextStyle(fontSize: 12, color: tsAmber, height: 1.35, fontWeight: FontWeight.w600),
          )
        else if (!saved)
          Text(
            'Nothing is saved for $company yet. Select the voucher types and save before comparing.',
            style: const TextStyle(fontSize: 12, color: tsAmber, height: 1.35, fontWeight: FontWeight.w600),
          )
        else if (savedNames.isEmpty)
          Text(
            'Nothing is ticked for $company. Select at least one voucher type and save before comparing.',
            style: const TextStyle(fontSize: 12, color: tsAmber, height: 1.35, fontWeight: FontWeight.w600),
          )
        else ...[
          Text(
            'Saved for $company',
            style: const TextStyle(fontSize: 12, color: tsMuted, height: 1.35),
          ),
          const SizedBox(height: 6),
          for (final name in savedNames)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(name, style: const TextStyle(color: tsInk, height: 1.35)),
            ),
        ],
      ],
    );
  }
}

class _VoucherTypeDialog extends StatefulWidget {
  const _VoucherTypeDialog({required this.controller});

  final CompareController controller;

  @override
  State<_VoucherTypeDialog> createState() => _VoucherTypeDialogState();
}

class _VoucherTypeDialogState extends State<_VoucherTypeDialog> {
  late final TextEditingController _search;
  late final Set<String> _ticks;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController();
    final saved = widget.controller.voucherTypesByCompany[widget.controller.company];
    _ticks = {...?saved};
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final query = _search.text.trim().toLowerCase();
        final names = controller.availableVoucherTypes
            .where((name) => query.isEmpty || name.toLowerCase().contains(query))
            .toList();
        return Dialog(
          backgroundColor: tsWhite,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: SizedBox(
            width: 420,
            height: 480,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select voucher types',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: tsInk),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    controller.company,
                    style: const TextStyle(fontSize: 12, color: tsMuted, height: 1.3),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Hirise Invoice Service is the job-card bill. Every other ticked type is a service bill. Leave receipts, journals, and parts sales unticked unless you mean to include them.',
                    style: TextStyle(fontSize: 12, color: tsMuted, height: 1.35),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _search,
                    decoration: _decoration(hint: 'Find a voucher type'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: tsLine),
                      ),
                      child: controller.loadingVoucherTypes
                          ? const Center(child: Text('Reading voucher types from Tally…'))
                          : names.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Text(
                                      controller.availableVoucherTypes.isEmpty
                                          ? 'No voucher types were read. Open the company in Tally, then try again.'
                                          : 'No voucher type matches that search.',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: tsMuted, height: 1.35),
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: names.length,
                                  itemBuilder: (context, index) {
                                    final name = names[index];
                                    return CheckboxListTile(
                                      dense: true,
                                      value: _ticks.contains(name),
                                      activeColor: tsGreen,
                                      title: Text(
                                        name,
                                        style: const TextStyle(fontSize: 13, color: tsInk),
                                      ),
                                      controlAffinity: ListTileControlAffinity.leading,
                                      onChanged: (value) {
                                        setState(() {
                                          if (value == true) {
                                            _ticks.add(name);
                                          } else {
                                            _ticks.remove(name);
                                          }
                                        });
                                      },
                                    );
                                  },
                                ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: controller.loadingVoucherTypes
                            ? null
                            : () => controller.loadVoucherTypes(force: true),
                        child: const Text('Reload'),
                      ),
                      const SizedBox(width: 4),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 4),
                      FilledButton(
                        onPressed: controller.company.isEmpty
                            ? null
                            : () {
                                controller.saveVoucherTypes(_ticks);
                                Navigator.of(context).pop();
                              },
                        style: FilledButton.styleFrom(
                          backgroundColor: tsGreen,
                          foregroundColor: tsWhite,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Save'),
                      ),
                    ],
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
