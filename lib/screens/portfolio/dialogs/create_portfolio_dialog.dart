import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/portfolio_state.dart';

class CreatePortfolioDialog extends StatefulWidget {
  const CreatePortfolioDialog({super.key});

  @override
  State<CreatePortfolioDialog> createState() => _CreatePortfolioDialogState();
}

class _CreatePortfolioDialogState extends State<CreatePortfolioDialog> {
  final _name = TextEditingController(text: '中国资产组合');
  final _owner = TextEditingController(text: '本地用户');
  String _currency = 'CNY';

  static const _currencies = ['CNY', 'HKD', 'USD', 'EUR', 'JPY'];

  @override
  void dispose() {
    _name.dispose();
    _owner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建组合'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '名称',
                hintText: '比如：我的 A 股组合',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _owner,
              decoration: const InputDecoration(labelText: '所有者'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _currency,
              decoration: const InputDecoration(labelText: '币种'),
              items: [
                for (final c in _currencies)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (v) => setState(() => _currency = v ?? 'CNY'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消')),
        ElevatedButton(
          onPressed: () async {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            await context.read<PortfolioState>().createPortfolio(
                  name: name,
                  currency: _currency,
                  owner: _owner.text.trim(),
                );
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('创建'),
        ),
      ],
    );
  }
}
