import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../widgets/common.dart';
import 'account_api.dart';

/// Tutor's own page: "My price and contact".
class TutorOfferScreen extends StatefulWidget {
  const TutorOfferScreen({super.key});
  @override
  State<TutorOfferScreen> createState() => _TutorOfferScreenState();
}

class _TutorOfferScreenState extends State<TutorOfferScreen> {
  final _api = AccountApi.instance;
  final _form = GlobalKey<FormState>();
  final _rate = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  String _unit = 'hour';
  String _mode = 'both';
  String _visibility = 'accepted';
  bool _free = false;
  bool _negotiable = false;
  bool _firstFree = false;
  bool _whatsapp = true;
  bool _calls = true;
  bool _loading = true;
  bool _busy = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _rate.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_api.available) return setState(() => _loading = false);
    try {
      final o = await _api.myTutorOffer();
      _free = o.rateUgx == 0;
      _rate.text = (o.rateUgx ?? 0) > 0 ? '${o.rateUgx}' : '';
      _unit = o.rateUnit;
      _mode = o.mode;
      _negotiable = o.negotiable;
      _firstFree = o.firstSessionFree;
      _phone.text = o.phone == null ? '' : _pretty(o.phone!);
      _whatsapp = o.phone == null ? true : o.whatsapp;
      _calls = o.phone == null ? true : o.calls;
      // Suggest their school email the first time.
      _email.text = o.email ?? Supabase.instance.client.auth.currentUser?.email ?? '';
      _visibility = o.visibility;
      setState(() => _loading = false);
    } catch (e) {
      setState(() => (_loading = false, _loadError = friendlyAccountError(e)));
    }
  }

  static String _pretty(String e164) =>
      e164.startsWith('+256') && e164.length == 13 ? '0${e164.substring(4, 7)} ${e164.substring(7)}' : e164;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final phone = _phone.text.trim().isEmpty ? null : normalizeUgPhone(_phone.text);
    final email = _email.text.trim().isEmpty ? null : _email.text.trim().toLowerCase();
    if (phone == null && email == null) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('No contact details?'),
          content: const Text('Students will only reach you through CampusLink requests. That is fine, but most students prefer a phone or email.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Add one')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save anyway')),
          ],
        ),
      );
      if (go != true) return;
    }
    setState(() => _busy = true);
    try {
      await _api.saveTutorOffer(TutorOffer(
        rateUgx: _free ? 0 : int.tryParse(_rate.text.replaceAll(RegExp(r'[^0-9]'), '')),
        rateUnit: _unit,
        negotiable: !_free && _negotiable,
        firstSessionFree: !_free && _firstFree,
        mode: _mode,
        phone: phone,
        whatsapp: phone != null && _whatsapp,
        calls: phone != null && _calls,
        email: email,
        visibility: _visibility,
      ));
      if (mounted) {
        showSnack(context, 'Saved.');
        Navigator.of(context).maybePop(true);
      }
    } catch (e) {
      if (mounted) showSnack(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final rate = int.tryParse(_rate.text.replaceAll(RegExp(r'[^0-9]'), ''));
    return Scaffold(
      appBar: AppBar(title: const Text('My price and contact')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_api.available
              ? const Center(child: Text('Available in the live app.'))
              : _loadError != null
                  ? Center(child: TextButton(onPressed: _load, child: Text('$_loadError  Retry')))
                  : Form(
                      key: _form,
                      child: ListView(padding: const EdgeInsets.all(16), children: [
                        _Section('Price', 'Students see this on your tutor card.'),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('I tutor for free'),
                          value: _free,
                          onChanged: (v) => setState(() => _free = v),
                        ),
                        if (!_free) ...[
                          Row(children: [
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                controller: _rate,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                                decoration: const InputDecoration(labelText: 'Price', prefixText: 'UGX '),
                                onChanged: (_) => setState(() {}),
                                validator: (v) {
                                  final n = int.tryParse(v ?? '');
                                  if (n == null || n <= 0) return 'Enter a price, or switch on "free"';
                                  if (n > 500000) return 'Max 500,000';
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: DropdownButtonFormField<String>(
                                initialValue: _unit,
                                decoration: const InputDecoration(labelText: 'Per'),
                                items: const [
                                  DropdownMenuItem(value: 'hour', child: Text('hour')),
                                  DropdownMenuItem(value: 'session', child: Text('session')),
                                  DropdownMenuItem(value: 'week', child: Text('week')),
                                  DropdownMenuItem(value: 'month', child: Text('month')),
                                ],
                                onChanged: (v) => setState(() => _unit = v ?? 'hour'),
                              ),
                            ),
                          ]),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Price can be discussed'),
                            value: _negotiable,
                            onChanged: (v) => setState(() => _negotiable = v ?? false),
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('First session is free'),
                            subtitle: const Text('A good way to win students'),
                            value: _firstFree,
                            onChanged: (v) => setState(() => _firstFree = v ?? false),
                          ),
                          Text('Prices for a single unit can still be set on that unit.',
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                        const SizedBox(height: 8),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'in_person', label: Text('On campus'), icon: Icon(Icons.groups_rounded)),
                            ButtonSegment(value: 'online', label: Text('Online'), icon: Icon(Icons.videocam_rounded)),
                            ButtonSegment(value: 'both', label: Text('Both')),
                          ],
                          selected: {_mode},
                          onSelectionChanged: (s) => setState(() => _mode = s.first),
                        ),
                        const SizedBox(height: 24),
                        _Section('Contact', 'Private. Only shown to the students you choose below.'),
                        TextFormField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          autofillHints: const [AutofillHints.telephoneNumber],
                          decoration: const InputDecoration(
                              labelText: 'Phone (optional)', hintText: '0772 123456', prefixIcon: Icon(Icons.phone_rounded)),
                          onChanged: (_) => setState(() {}),
                          validator: (v) => (v ?? '').trim().isEmpty || normalizeUgPhone(v!) != null
                              ? null
                              : 'Use a number like 0772 123456 or +256 772 123456',
                        ),
                        if (_phone.text.trim().isNotEmpty) ...[
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('This number is on WhatsApp'),
                            value: _whatsapp,
                            onChanged: (v) => setState(() => _whatsapp = v ?? false),
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Students may call me'),
                            subtitle: const Text('Turn off to allow messages only'),
                            value: _calls,
                            onChanged: (v) => setState(() => _calls = v ?? false),
                          ),
                        ],
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(labelText: 'Email (optional)', prefixIcon: Icon(Icons.mail_outline)),
                          validator: (v) {
                            final s = (v ?? '').trim();
                            if (s.isEmpty) return null;
                            return RegExp(r'^[^@\s]+@[^@\s]+\.[a-zA-Z]{2,}$').hasMatch(s) ? null : 'Check the email';
                          },
                        ),
                        const SizedBox(height: 16),
                        Text('Who can see my phone and email?', style: Theme.of(context).textTheme.titleSmall),
                        RadioGroup<String>(
                          groupValue: _visibility,
                          onChanged: (v) => setState(() => _visibility = v ?? 'accepted'),
                          child: const Column(children: [
                            RadioListTile<String>(
                              contentPadding: EdgeInsets.zero,
                              value: 'accepted',
                              title: Text('Only students whose request I accept'),
                              subtitle: Text('Safest. Recommended.'),
                            ),
                            RadioListTile<String>(
                              contentPadding: EdgeInsets.zero,
                              value: 'signed_in',
                              title: Text('Any signed-in student'),
                              subtitle: Text('Students can contact you before sending a request.'),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 8),
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.visibility_rounded),
                            title: const Text('Students will see'),
                            subtitle: Text(
                                '${TutorOffer.priceLabel(rateUgx: _free ? 0 : rate, unit: _unit, negotiable: _negotiable, firstFree: _firstFree)}'
                                ' · ${_mode == 'both' ? 'on campus or online' : _mode == 'online' ? 'online' : 'on campus'}',
                                style: TextStyle(color: muted)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _busy ? null : _save,
                          child: _busy
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Save'),
                        ),
                        const SizedBox(height: 8),
                        Text('Never share your Mobile Money PIN or ask students to pay before the first session '
                            'without agreeing first. Report anyone who pressures you.',
                            style: Theme.of(context).textTheme.bodySmall),
                      ]),
                    ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.subtitle);
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
      );
}

/// On a tutor's page: shows Call / WhatsApp / Email when allowed, otherwise
/// explains how to get them ("send a request first").
class TutorContactCard extends StatefulWidget {
  const TutorContactCard({super.key, required this.tutorId, required this.tutorName});
  final String tutorId;
  final String tutorName;
  @override
  State<TutorContactCard> createState() => _TutorContactCardState();
}

class _TutorContactCardState extends State<TutorContactCard> {
  TutorContact? _c;
  bool _busy = false;
  String? _error;

  Future<void> _reveal() async {
    setState(() => (_busy = true, _error = null));
    try {
      final c = await AccountApi.instance.tutorContact(widget.tutorId);
      if (mounted) setState(() => _c = c);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyAccountError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _go(Uri u) async {
    if (!await launchUrl(u, mode: LaunchMode.externalApplication) && mounted) {
      showSnack(context, 'Could not open that app on this device.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AccountApi.instance.available) return const SizedBox.shrink();
    final c = _c;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.contact_phone_rounded),
            const SizedBox(width: 10),
            Expanded(child: Text('Contact ${widget.tutorName}', style: const TextStyle(fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 10),
          if (c == null)
            OutlinedButton(
              onPressed: _busy ? null : _reveal,
              child: _busy
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Show contact details'),
            )
          else if (!c.visible)
            Text(c.explain, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
          else
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (c.phone != null && c.whatsapp)
                FilledButton.icon(
                  icon: const Icon(Icons.chat_rounded),
                  label: const Text('WhatsApp'),
                  onPressed: () => _go(Uri.parse('https://wa.me/${c.phone!.substring(1)}?text='
                      '${Uri.encodeComponent('Hi ${widget.tutorName}, I found you on CampusLink.')}')),
                ),
              if (c.phone != null && c.calls)
                OutlinedButton.icon(
                    icon: const Icon(Icons.call_rounded), label: Text(c.phone!), onPressed: () => _go(Uri(scheme: 'tel', path: c.phone))),
              if (c.phone != null && !c.calls)
                OutlinedButton.icon(
                    icon: const Icon(Icons.sms_rounded), label: const Text('Text message'), onPressed: () => _go(Uri(scheme: 'sms', path: c.phone))),
              if (c.email != null)
                OutlinedButton.icon(
                  icon: const Icon(Icons.mail_rounded),
                  label: Text(c.email!),
                  onPressed: () => _go(Uri(scheme: 'mailto', path: c.email, query: 'subject=${Uri.encodeComponent('Tutoring (CampusLink)')}')),
                ),
            ]),
          if (_error != null) ...[const SizedBox(height: 8), Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))],
        ]),
      ),
    );
  }
}
