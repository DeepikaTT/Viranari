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
  List<TrustedContact> _contacts = const [];
  bool _loading = true;
  String? _error;
  final _contactCache = TrustedContactCacheStore();

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
      await _contactCache.save(contacts);
      if (mounted) setState(() => _contacts = contacts);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  Future<void> _editMyPhone() async {
    final controller = TextEditingController(text: widget.session.user?.phoneE164 ?? '+91');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your emergency phone number'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Mobile number with country code',
            hintText: '+919876543210',
            helperText: 'Trusted contacts can call or prepare an emergency SMS to this number after you accept each other.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final phone = controller.text.trim();
    if (!RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(phone)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Use international format, for example +919876543210.')),
        );
      }
      return;
    }
    try {
      await widget.session.updatePhone(phone);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Emergency phone number updated.')));
      }
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
              const Text('Share this one-time code with your trusted contact. They must sign in and accept it before they receive SOS alerts.'),
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
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You are now an active trusted contact.')));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _remove(TrustedContact contact) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove trusted contact?'),
        content: Text('${contact.name} will not receive future SOS alerts from you.'),
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
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 110),
        children: [
          Text('Trusted Circle', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, color: ViraColors.plum)),
          const SizedBox(height: 6),
          const Text('Every contact must opt in before they can receive your SOS. Phone numbers are revealed only after consent.', style: TextStyle(color: ViraColors.mutedPlum)),
          const SizedBox(height: 14),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: ViraColors.lilacStrong),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: ViraColors.lilac,
                  child: Icon(Icons.phone_in_talk_outlined, color: ViraColors.plum),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Your emergency phone', style: TextStyle(fontWeight: FontWeight.w900)),
                      Text(
                        widget.session.user?.phoneE164 ?? 'Not set — calling and SMS fallback cannot work',
                        style: TextStyle(
                          color: widget.session.user?.phoneE164 == null ? ViraColors.pinkDark : ViraColors.mutedPlum,
                          fontWeight: widget.session.user?.phoneE164 == null ? FontWeight.w800 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(onPressed: _editMyPhone, child: Text(widget.session.user?.phoneE164 == null ? 'Add' : 'Edit')),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: FilledButton.icon(onPressed: _invite, icon: const Icon(Icons.person_add_alt_1), label: const Text('Invite'))),
              const SizedBox(width: 10),
              Expanded(child: FilledButton.tonalIcon(onPressed: _accept, icon: const Icon(Icons.verified_user_outlined), label: const Text('Accept code'))),
            ],
          ),
          const SizedBox(height: 20),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()))
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: ViraColors.pinkDark))
          else if (_contacts.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: ViraColors.lilac, borderRadius: BorderRadius.circular(24)),
              child: const Column(
                children: [
                  Icon(Icons.group_outlined, size: 44, color: ViraColors.plum),
                  SizedBox(height: 12),
                  Text('No trusted contacts yet', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                  SizedBox(height: 5),
                  Text('Invite someone who already has a ViraNari account.', textAlign: TextAlign.center),
                ],
              ),
            )
          else
            ..._contacts.map(
              (c) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    children: [
                      CircleAvatar(backgroundColor: c.status == 'active' ? ViraColors.successSoft : ViraColors.lilac, child: Icon(c.status == 'active' ? Icons.verified_user : Icons.hourglass_top, color: c.status == 'active' ? ViraColors.success : ViraColors.plum)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.alias, style: const TextStyle(fontWeight: FontWeight.w900)),
                            Text('${c.name} · ${c.email}', style: const TextStyle(color: ViraColors.mutedPlum)),
                            if (c.status == 'active')
                              Text(c.phoneE164 ?? 'Phone number not set', style: TextStyle(color: c.phoneE164 == null ? ViraColors.pinkDark : ViraColors.mutedPlum, fontSize: 12, fontWeight: c.phoneE164 == null ? FontWeight.w800 : FontWeight.w500)),
                            Text(c.status.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: c.status == 'active' ? ViraColors.success : ViraColors.warning)),
                          ],
                        ),
                      ),
                      IconButton(onPressed: () => _remove(c), icon: const Icon(Icons.delete_outline), tooltip: 'Remove'),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
