import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class MediChipInputField extends StatefulWidget {
  final String label;
  final String hint;
  final List<String> suggestions;
  final String initialValue; // Comma-separated values
  final ValueChanged<String> onChanged;
  final bool isRequired;
  final String? Function(String?)? validator;

  const MediChipInputField({
    super.key,
    required this.label,
    required this.hint,
    required this.suggestions,
    required this.initialValue,
    required this.onChanged,
    this.isRequired = false,
    this.validator,
  });

  @override
  State<MediChipInputField> createState() => _MediChipInputFieldState();
}

class _MediChipInputFieldState extends State<MediChipInputField> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  List<String> _selectedItems = [];
  List<String> _filteredSuggestions = [];
  bool _hasOpened = false;

  @override
  void initState() {
    super.initState();
    _parseInitialValue();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant MediChipInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue) {
      _parseInitialValue();
    }
  }

  @override
void dispose() {
  _focusNode.removeListener(_onFocusChange);
  _removeOverlay();
  _controller.dispose();
  _focusNode.dispose();
  super.dispose();
}

  void _parseInitialValue() {
    if (widget.initialValue.trim().isEmpty) {
      _selectedItems = [];
    } else {
      _selectedItems = widget.initialValue
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _showOverlay();
    } else {
      _removeOverlay();
    }
  }

  void _updateSuggestions(String query) {
    final cleanQuery = query.trim().toLowerCase();
    setState(() {
      if (cleanQuery.isEmpty) {
        _filteredSuggestions = widget.suggestions
            .where((item) => !_selectedItems.contains(item))
            .take(5)
            .toList();
      } else {
        _filteredSuggestions = widget.suggestions
            .where((item) =>
                item.toLowerCase().contains(cleanQuery) &&
                !_selectedItems.contains(item))
            .toList();
      }
    });
    _overlayEntry?.markNeedsBuild();
  }

  void _addItem(String item) {
    final trimmed = item.trim();
    if (trimmed.isEmpty) return;

    if (!_selectedItems.contains(trimmed)) {
      setState(() {
        _selectedItems.add(trimmed);
      });
      widget.onChanged(_selectedItems.join(', '));
    }
    _controller.clear();
    _focusNode.unfocus();
  }

  void _removeItem(String item) {
    setState(() {
      _selectedItems.remove(item);
    });
    widget.onChanged(_selectedItems.join(', '));
    _updateSuggestions(_controller.text);
    _overlayEntry?.markNeedsBuild();
  }

  void _showOverlay() {
    _removeOverlay();
    if (!mounted) return;

    _updateSuggestions(_controller.text);

    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, size.height + 4),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            color: AppTheme.surface,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  ..._filteredSuggestions.map((suggestion) {
                    return ListTile(
                      dense: true,
                      title: Text(
                        suggestion,
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      trailing: const Icon(Icons.add, size: 16, color: AppTheme.primary),
                      onTap: () => _addItem(suggestion),
                    );
                  }),
                  if (_controller.text.trim().isNotEmpty &&
                      !_filteredSuggestions.contains(_controller.text.trim()) &&
                      !_selectedItems.contains(_controller.text.trim()))
                    ListTile(
                      dense: true,
                      tileColor: AppTheme.surfaceVariant,
                      leading: const Icon(Icons.add_circle_outline, size: 18, color: AppTheme.primary),
                      title: Text(
                        'Add "${_controller.text.trim()}" as custom entry',
                        style: const TextStyle(
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary,
                        ),
                      ),
                      onTap: () => _addItem(_controller.text.trim()),
                    ),
                  if (_filteredSuggestions.isEmpty && _controller.text.trim().isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        'Type to search or add...',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.textTertiary, fontSize: 13),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
    setState(() {
      _hasOpened = true;
    });
  }

  void _removeOverlay() {
  _overlayEntry?.remove();
  _overlayEntry = null;
}

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CompositedTransformTarget(
          link: _layerLink,
          child: TextFormField(
            controller: _controller,
            focusNode: _focusNode,
            onChanged: _updateSuggestions,
            onFieldSubmitted: (val) {
              if (val.trim().isNotEmpty) {
                _addItem(val.trim());
              }
            },
            validator: (val) {
              if (widget.validator != null) {
                return widget.validator!(_selectedItems.join(', '));
              }
              return null;
            },
            style: const TextStyle(fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              labelText: widget.isRequired ? '${widget.label} *' : widget.label,
              labelStyle: TextStyle(
                color: widget.isRequired ? AppTheme.danger : AppTheme.textSecondary,
              ),
              hintText: _selectedItems.isEmpty ? widget.hint : '',
              hintStyle: TextStyle(color: AppTheme.textTertiary),
              floatingLabelBehavior: FloatingLabelBehavior.always,
              filled: true,
              fillColor: AppTheme.surface,
              prefixIcon: const Icon(Icons.search, color: AppTheme.primary, size: 20),
              suffixIcon: _controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _controller.clear();
                        _updateSuggestions('');
                      },
                    )
                  : Icon(
                      _hasOpened ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      color: AppTheme.textTertiary,
                    ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.primary, width: 2),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.danger),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.danger, width: 2),
              ),
            ),
          ),
        ),
        if (_selectedItems.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _selectedItems.map((item) {
              return Chip(
                label: Text(
                  item,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                labelStyle: const TextStyle(color: AppTheme.primary),
                deleteIcon: const Icon(Icons.cancel, size: 16, color: AppTheme.primary),
                onDeleted: () => _removeItem(item),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.2)),
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}
