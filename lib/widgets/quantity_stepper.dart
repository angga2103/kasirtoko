import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/app_theme.dart';

/// Responsive quantity stepper with manual editable numeric input:
/// [-]  [ 10 ]  [+]
/// Designed so the numeric value is always clearly visible even in compact dialogs.
class QuantityStepper extends StatefulWidget {
  final double value;
  final double minValue;
  final double? maxValue;
  final double step;
  final bool allowDecimal;
  final ValueChanged<double> onChanged;
  final bool compact;
  final String? unitLabel;

  const QuantityStepper({
    super.key,
    required this.value,
    this.minValue = 0,
    this.maxValue,
    this.step = 1,
    this.allowDecimal = false,
    required this.onChanged,
    this.compact = false,
    this.unitLabel,
  });

  @override
  State<QuantityStepper> createState() => _QuantityStepperState();
}

class _QuantityStepperState extends State<QuantityStepper> {
  late TextEditingController _ctrl;
  final FocusNode _focus = FocusNode();

  String _formatNum(double v) {
    if (!widget.allowDecimal || v == v.truncateToDouble()) {
      return v.toInt().toString();
    }
    return v.toStringAsFixed(1);
  }

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _formatNum(widget.value));
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        _commitTypedValue();
      }
    });
  }

  @override
  void didUpdateWidget(covariant QuantityStepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && oldWidget.value != widget.value) {
      final newText = _formatNum(widget.value);
      if (_ctrl.text != newText) {
        _ctrl.text = newText;
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commitTypedValue() {
    final parsed = double.tryParse(_ctrl.text.replaceAll(',', '.').trim());
    if (parsed == null) {
      _ctrl.text = _formatNum(widget.value);
      return;
    }
    double clamped = parsed;
    if (clamped < widget.minValue) clamped = widget.minValue;
    if (widget.maxValue != null && clamped > widget.maxValue!) {
      clamped = widget.maxValue!;
    }
    _ctrl.text = _formatNum(clamped);
    if (clamped != widget.value) {
      widget.onChanged(clamped);
    }
  }

  void _stepBy(double delta) {
    FocusScope.of(context).unfocus();
    double next = widget.value + delta;
    if (next < widget.minValue) next = widget.minValue;
    if (widget.maxValue != null && next > widget.maxValue!) {
      next = widget.maxValue!;
    }
    _ctrl.text = _formatNum(next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final double btnSize = widget.compact ? 30 : 34;
    final double fieldWidth = widget.compact ? 54 : 64;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepBtn(
          icon: Icons.remove_rounded,
          size: btnSize,
          color: AppTheme.accentRed,
          onTap: () => _stepBy(-widget.step),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: fieldWidth,
          height: btnSize,
          child: TextField(
            controller: _ctrl,
            focusNode: _focus,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.numberWithOptions(decimal: widget.allowDecimal),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                widget.allowDecimal ? RegExp(r'[0-9.,]') : RegExp(r'[0-9]'),
              ),
            ],
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: widget.compact ? 13 : 14,
              color: AppTheme.textDark,
            ),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppTheme.primaryGreen, width: 1.6),
              ),
            ),
            onSubmitted: (_) => _commitTypedValue(),
            onChanged: (val) {
              final parsed = double.tryParse(val.replaceAll(',', '.').trim());
              if (parsed != null && parsed >= widget.minValue) {
                if (widget.maxValue == null || parsed <= widget.maxValue!) {
                  widget.onChanged(parsed);
                }
              }
            },
          ),
        ),
        if (widget.unitLabel != null && widget.unitLabel!.isNotEmpty) ...[
          const SizedBox(width: 4),
          Text(
            widget.unitLabel!,
            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600),
          ),
        ],
        const SizedBox(width: 4),
        _StepBtn(
          icon: Icons.add_rounded,
          size: btnSize,
          color: AppTheme.primaryGreen,
          onTap: (widget.maxValue == null || widget.value < widget.maxValue!)
              ? () => _stepBy(widget.step)
              : null,
        ),
      ],
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color color;
  final VoidCallback? onTap;

  const _StepBtn({
    required this.icon,
    required this.size,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = onTap != null;
    return Material(
      color: active ? color.withValues(alpha: 0.1) : Colors.grey.shade200,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: size * 0.56,
            color: active ? color : Colors.grey.shade400,
          ),
        ),
      ),
    );
  }
}
