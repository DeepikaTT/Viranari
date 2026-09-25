import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/storage.dart';
import '../core/theme.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key, required this.session});
  final AppSession session;

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final _phoneStore = TrustedPhoneStore();
  List<TrustedContact> _contacts = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final contacts = await widget.session.api.contacts();
      await _phoneStore.saveFromContacts(contacts);
      if (mounted) setState(() => _contacts = contacts);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _validPhone(String value) => RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(value);

  Future<void> _editOwnPhone() async {
    final controller = TextEditingController(text: widget.session.user?.phoneE164 ?? '+91');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your SMS/call number'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'International format',
            helperText: 'Example: +919876543210',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final phone = controller.text.trim().replaceAll(' ', '');
    if (!_validPhone(phone)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Use +country-code format, e.g. +919876543210.')));
      return;
    }
    try {
      await widget.session.updatePhone(phone);
      if (mounted) setState(() {});
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _invite() async {
    final email = TextEditingController();
    final alias = TextEditingController(text: 'Trusted contact');
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invite trusted contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Their registered email')),
            const SizedBox(height: 12),
            TextField(controller: alias, decoration: const InputDecoration(labelText: 'Relationship / label')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create invite')),
        ],
      ),
    );
    if (result != true || email.text.trim().isEmpty) return;
    try {
      final contact = await widget.session.api.inviteContact(email.text.trim(), alias.text.trim());
      await _load();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Consent code created'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Share this one-time code. Their phone number stays private until they accept the Trusted Circle invitation.'),
              const SizedBox(height: 16),
              SelectableText(contact.inviteToken ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: ViraColors.plum)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: contact.inviteToken ?? ''));
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invite code copied')));
              },
              child: const Text('Copy'),
            ),
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
          ],
        ),
      );
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _accept() async {
    final code = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Accept trusted-circle invite'),
        content: TextField(controller: code, decoration: const InputDecoration(labelText: 'Invite code')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Accept')),
        ],
      ),
    );
    if (ok != true || code.text.trim().isEmpty) return;
    try {
      await widget.session.api.acceptInvite(code.text.trim());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trusted Circle consent accepted.')));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _remove(TrustedContact contact) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove trusted contact?'),
        content: Text('${contact.name} will not receive future SOS alerts or SMS fallback from you.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (yes != true) return;
    await widget.session.api.removeContact(contact.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
        children: [
          Text('Trusted Circle', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, color: ViraColors.plum)),
          const SizedBox(height: 5),
          const Text('Only accepted people receive your SOS and become eligible for SMS fallback.', style: TextStyle(color: ViraColors.mutedPlum)),
          const SizedBox(height: 18),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(backgroundColor: ViraColors.successSoft, child: Icon(Icons.phone_iphone_rounded, color: ViraColors.success)),
            title: const Text('Your emergency number', style: TextStyle(fontWeight: FontWeight.w900)),
            subtitle: Text(widget.session.user?.phoneE164 ?? 'Not configured'),
            trailing: TextButton(onPressed: _editOwnPhone, child: const Text('Edit')),
          ),
          const Divider(),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: FilledButton.icon(onPressed: _invite, icon: const Icon(Icons.person_add_alt_1_rounded), label: const Text('Invite'))),
              const SizedBox(width: 10),
              Expanded(child: OutlinedButton.icon(onPressed: _accept, icon: const Icon(Icons.verified_user_outlined), label: const Text('Accept code'))),
            ],
          ),
          const SizedBox(height: 20),
          Text('People', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()))
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: ViraColors.pinkDark))
          else if (_contacts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Column(children: [
                Icon(Icons.group_outlined, size: 42, color: ViraColors.mutedPlum),
                SizedBox(height: 8),
                Text('No trusted contacts yet', style: TextStyle(fontWeight: FontWeight.w900)),
              ]),
            )
          else
            ..._contacts.map((c) => Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: c.status == 'active' ? ViraColors.successSoft : ViraColors.lilac,
                        child: Icon(c.status == 'active' ? Icons.verified_user_rounded : Icons.hourglass_top_rounded, color: c.status == 'active' ? ViraColors.success : ViraColors.warning),
                      ),
                      title: Text(c.alias, style: const TextStyle(fontWeight: FontWeight.w900)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${c.name} · ${c.email}'),
                          if (c.phoneE164 != null) Text('SMS ${c.phoneE164}', style: const TextStyle(color: ViraColors.success, fontWeight: FontWeight.w700)),
                        ],
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) { if (value == 'remove') _remove(c); },
                        itemBuilder: (_) => [
                          PopupMenuItem(enabled: false, child: Text(c.status.toUpperCase())),
                          const PopupMenuItem(value: 'remove', child: Text('Remove')),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                  ],
                )),
        ],
      ),
    );
  }
}
