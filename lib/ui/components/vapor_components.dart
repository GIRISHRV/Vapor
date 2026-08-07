import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme_provider.dart';

// --- Vapor Button ---
class VaporButton extends ConsumerWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final bool isLoading;

  const VaporButton({
    super.key,
    required this.child,
    this.onPressed,
    this.isPrimary = true,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(designStyleProvider);
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;

    void Function()? action;
    if (onPressed != null) {
      action = () {
        HapticFeedback.lightImpact();
        if (!isLoading) onPressed!();
      };
    }

    Widget btn;
    if (style == AppDesignStyle.fluent) {
      // Fluent UI Style Button (Pure Dart)
      btn = Container(
        decoration: BoxDecoration(
          color: isPrimary 
              ? (isDark ? const Color(0xFF60CDFF) : const Color(0xFF005FB8))
              : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06)),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isPrimary ? Colors.transparent : (isDark ? Colors.white12 : Colors.black12),
            width: 1,
          ),
        ),
        child: InkWell(
          onTap: action,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: DefaultTextStyle(
              style: TextStyle(
                color: isPrimary 
                    ? (isDark ? Colors.black : Colors.white)
                    : (isDark ? Colors.white : Colors.black),
                fontWeight: FontWeight.w600,
              ),
              child: isLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : child,
            ),
          ),
        ),
      );
    } else if (style == AppDesignStyle.cupertino) {
      btn = CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        color: isPrimary ? CupertinoColors.activeBlue : (isDark ? Colors.white10 : Colors.black12),
        borderRadius: BorderRadius.circular(8),
        onPressed: action,
        child: isLoading ? const CupertinoActivityIndicator() : child,
      );
    } else {
      btn = isPrimary
          ? FilledButton(onPressed: action, child: isLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : child)
          : OutlinedButton(onPressed: action, child: isLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : child);
    }

    return btn.animate().scale(
      duration: 150.ms,
      curve: Curves.easeOut,
      begin: const Offset(0.95, 0.95),
      end: const Offset(1.0, 1.0),
    );
  }
}

// --- Vapor Card ---
class VaporCard extends ConsumerWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const VaporCard({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(designStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (style == AppDesignStyle.fluent) {
      // Fluent UI Acrylic (Pure Dart)
      return ClipRRect(
        borderRadius: BorderRadius.circular(8.0),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: kIsWeb ? 4 : 20,
            sigmaY: kIsWeb ? 4 : 20,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.black.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.6),
              border: Border.all(color: isDark ? Colors.white12 : Colors.black12, width: 1),
              borderRadius: BorderRadius.circular(8.0),
            ),
            padding: padding ?? const EdgeInsets.all(16.0),
            child: child,
          ),
        ),
      );
    } else if (style == AppDesignStyle.cupertino) {
      // Apple Glassmorphism
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: kIsWeb ? 8 : 30,
            sigmaY: kIsWeb ? 8 : 30,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
              border: Border.all(color: isDark ? Colors.white24 : Colors.black12),
              borderRadius: BorderRadius.circular(16),
            ),
            padding: padding ?? const EdgeInsets.all(16.0),
            child: child,
          ),
        ),
      );
    } else {
      // Material
      return Card(
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: padding ?? const EdgeInsets.all(16.0),
          child: child,
        ),
      );
    }
  }
}

// --- Vapor Scaffold ---
class VaporScaffold extends ConsumerWidget {
  final dynamic title; // String or Widget
  final Widget body;
  final Widget? floatingActionButton;
  final List<Widget>? actions;
  final Widget? leading;
  final Widget? bottomNavigationBar;
  final bool hideAppBar;

  const VaporScaffold({
    super.key,
    this.title,
    required this.body,
    this.floatingActionButton,
    this.actions,
    this.leading,
    this.bottomNavigationBar,
    this.hideAppBar = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(designStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Widget? titleWidget = title is String
        ? Text(title as String, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16))
        : (title as Widget?);

    if (style == AppDesignStyle.fluent) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF202020) : const Color(0xFFF3F3F3),
        appBar: hideAppBar ? null : AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: leading,
          title: titleWidget,
          actions: actions,
          centerTitle: false,
        ),
        body: body,
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: bottomNavigationBar,
      );
    } else if (style == AppDesignStyle.cupertino) {
      return Scaffold(
        backgroundColor: isDark ? CupertinoColors.black : CupertinoColors.systemGroupedBackground,
        appBar: hideAppBar ? null : CupertinoNavigationBar(
          leading: leading,
          middle: titleWidget,
          trailing: actions != null ? Row(mainAxisSize: MainAxisSize.min, children: actions!) : null,
          backgroundColor: isDark ? Colors.black.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.5),
        ),
        body: SafeArea(child: body),
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: bottomNavigationBar,
      );
    } else {
      return Scaffold(
        appBar: hideAppBar ? null : AppBar(
          leading: leading,
          title: titleWidget,
          actions: actions,
        ),
        body: body,
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: bottomNavigationBar,
      );
    }
  }
}

// --- Vapor TextField ---
class VaporTextField extends ConsumerWidget {
  final TextEditingController controller;
  final String placeholder;
  final bool obscureText;
  final Function(String)? onChanged;
  final Widget? suffix;
  final Widget? prefix;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  const VaporTextField({
    super.key,
    required this.controller,
    required this.placeholder,
    this.obscureText = false,
    this.onChanged,
    this.suffix,
    this.prefix,
    this.keyboardType,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(designStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (style == AppDesignStyle.fluent) {
      return Container(
        height: 40,
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border(bottom: BorderSide(color: isDark ? Colors.white54 : Colors.black54, width: 1.5)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            if (prefix != null) ...[
              prefix!,
              const SizedBox(width: 8),
            ],
            Expanded(
              child: TextField(
                controller: controller,
                obscureText: obscureText,
                onChanged: onChanged,
                keyboardType: keyboardType,
                inputFormatters: inputFormatters,
                decoration: InputDecoration(
                  hintText: placeholder,
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                style: const TextStyle(fontSize: 14),
              ),
            ),
            ?suffix,
          ],
        ),
      );
    } else if (style == AppDesignStyle.cupertino) {
      return CupertinoTextField(
        controller: controller,
        placeholder: placeholder,
        obscureText: obscureText,
        onChanged: onChanged,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        prefix: prefix,
        suffix: suffix,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
        ),
      );
    } else {
      return TextField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        decoration: InputDecoration(
          labelText: placeholder,
          prefixIcon: prefix,
          suffixIcon: suffix,
          border: const OutlineInputBorder(),
        ),
        obscureText: obscureText,
        onChanged: onChanged,
      );
    }
  }
}

// --- Vapor Progress ---
class VaporProgress extends ConsumerWidget {
  const VaporProgress({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(designStyleProvider);
    if (style == AppDesignStyle.cupertino || style == AppDesignStyle.fluent) {
      return const CupertinoActivityIndicator(radius: 12);
    }
    return const CircularProgressIndicator();
  }
}

// --- Vapor ListTile ---
class VaporListTile extends ConsumerWidget {
  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  const VaporListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(designStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (style == AppDesignStyle.fluent) {
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 16)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DefaultTextStyle(
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                      child: title,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      DefaultTextStyle(
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                        child: subtitle!,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 16), trailing!],
            ],
          ),
        ),
      );
    } else if (style == AppDesignStyle.cupertino) {
      return CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        onPressed: onTap,
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 16)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DefaultTextStyle(
                    style: TextStyle(
                      fontSize: 17,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                    child: title,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    DefaultTextStyle(
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                      child: subtitle!,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 16), trailing!],
          ],
        ),
      );
    } else {
      return ListTile(
        title: title,
        subtitle: subtitle,
        leading: leading,
        trailing: trailing,
        onTap: onTap,
      );
    }
  }
}

// --- Formatters ---
class MistCodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text;
    text = text.replaceAll(RegExp(r'[^0-9]'), '');
    if (text.length > 9) {
      text = text.substring(0, 9);
    }
    var newText = '';
    for (int i = 0; i < text.length; i++) {
      if (i == 3 || i == 6) newText += '-';
      newText += text[i];
    }
    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}
