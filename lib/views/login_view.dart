import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../stores/session_store.dart';
import '../stores/ui_store.dart';
import '../theme/theme.dart';

/// The sign-in / initial-setup screen. Mirrors Swift `LoginView` (the compact
/// iPhone layout — the iCloud-keychain sync section is dropped on Android).
class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

enum _LoginField { server, password }

class _LoginViewState extends State<LoginView> {
  final _serverCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _proxyCtrl = TextEditingController();
  final _serverFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _advancedOpen = false;
  bool _loading = false;
  String _error = '';
  _LoginField? _focused;

  @override
  void initState() {
    super.initState();
    final session = context.read<SessionStore>();
    _serverCtrl.text = session.baseURL;
    _proxyCtrl.text = session.proxyCookie;
    _serverFocus.addListener(_syncFocus);
    _passwordFocus.addListener(_syncFocus);
  }

  void _syncFocus() {
    setState(() {
      if (_serverFocus.hasFocus) {
        _focused = _LoginField.server;
      } else if (_passwordFocus.hasFocus) {
        _focused = _LoginField.password;
      } else {
        _focused = null;
      }
    });
  }

  @override
  void dispose() {
    _serverCtrl.dispose();
    _passwordCtrl.dispose();
    _proxyCtrl.dispose();
    _serverFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _applyServer() {
    final url = APIClient.normalize(_serverCtrl.text);
    _serverCtrl.text = url;
    final session = context.read<SessionStore>();
    session.baseURL = url;
    session.proxyCookie = _proxyCtrl.text;
  }

  Future<void> _submit() async {
    if (_loading) return;
    setState(() => _error = '');
    _applyServer();
    final session = context.read<SessionStore>();
    if (session.baseURL.isEmpty) {
      setState(() => _error = '请填写服务器地址');
      _serverFocus.requestFocus();
      return;
    }
    if (_passwordCtrl.text.length < 8) {
      setState(() => _error = '密码至少 8 位');
      _passwordFocus.requestFocus();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      await session.login(password: _passwordCtrl.text);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    final ui = context.watch<UIStore>();
    final accent = ui.themeAccent;
    return Scaffold(
      backgroundColor: MX.heroBase,
      body: Stack(
        children: [
          const Positioned.fill(child: _LoginBackground()),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _compactHeroPanel(accent),
                  const SizedBox(height: 24),
                  _signInCard(session, accent),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Hero panel ─────────────────────────────────────────────────────────

  Widget _compactHeroPanel(ThemeAccent accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _brandMark(accent),
        const SizedBox(height: 34),
        const Text(
          '你的音乐，\n在这里继续播放。',
          style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold, height: 1.15),
        ),
        const SizedBox(height: 16),
        _featureLabels(),
      ],
    );
  }

  Widget _brandMark(ThemeAccent accent) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [accent.color, accent.deepColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(15),
            boxShadow: [BoxShadow(color: accent.color.withOpacity(0.34), blurRadius: 18, offset: const Offset(0, 8))],
          ),
          child: const Icon(Icons.graphic_eq, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('MUSICX',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 2.8)),
            const SizedBox(height: 3),
            Text('YOUR PERSONAL SOUNDSPACE',
                style: TextStyle(color: Colors.white.withOpacity(0.42), fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 1.1)),
          ],
        ),
      ],
    );
  }

  Widget _featureLabels() {
    Widget label(String title, IconData icon) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.white.withOpacity(0.62)),
            const SizedBox(width: 6),
            Text(title, style: TextStyle(color: Colors.white.withOpacity(0.62), fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        );
    return Row(
      children: [
        label('个人媒体库', Icons.queue_music),
        const SizedBox(width: 16),
        label('无缝续播', Icons.sync),
      ],
    );
  }

  // ── Sign-in card ───────────────────────────────────────────────────────

  Widget _signInCard(SessionStore session, ThemeAccent accent) {
    final setup = session.setupRequired;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MX.panel.withOpacity(0.96),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.32), blurRadius: 36, offset: const Offset(0, 18))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(setup ? '欢迎使用' : '欢迎回来',
              style: TextStyle(color: accent.color, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(setup ? '设置你的访问密码' : '登录到你的音乐库',
              style: TextStyle(color: MX.fg, fontSize: 27, fontWeight: FontWeight.bold)),
          const SizedBox(height: 9),
          Text(setup ? '设置完成后，即可连接并开始管理个人音乐。' : '输入服务器地址与密码，继续你的聆听。',
              style: TextStyle(color: MX.dim, fontSize: 13, height: 1.3)),
          const SizedBox(height: 28),
          _serverField(accent),
          const SizedBox(height: 18),
          _passwordField(accent),
          _advancedToggle(),
          if (_advancedOpen) _advancedSection(),
          if (_error.isNotEmpty) ...[
            _errorMessage(),
            const SizedBox(height: 14),
          ] else
            const SizedBox(height: 4),
          _submitButton(setup),
          const SizedBox(height: 17),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.shield_outlined, size: 13, color: MX.dim),
              const SizedBox(width: 6),
              Flexible(
                child: Text('连接信息仅用于访问你的个人音乐库',
                    style: TextStyle(color: MX.dim, fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _serverField(ThemeAccent accent) {
    final active = _focused == _LoginField.server;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _inputLabel('服务器地址'),
        const SizedBox(height: 8),
        _inputBox(
          active: active,
          child: Row(
            children: [
              Icon(Icons.lan_outlined, size: 18, color: active ? accent.color : MX.dim),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _serverCtrl,
                  focusNode: _serverFocus,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  style: TextStyle(color: MX.fg),
                  decoration: _plainInput('http://192.168.1.10:8080'),
                  onSubmitted: (_) {
                    _applyServer();
                    _passwordFocus.requestFocus();
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _passwordField(ThemeAccent accent) {
    final active = _focused == _LoginField.password;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _inputLabel('密码'),
        const SizedBox(height: 8),
        _inputBox(
          active: active,
          child: Row(
            children: [
              Icon(Icons.lock_outline, size: 18, color: active ? accent.color : MX.dim),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _passwordCtrl,
                  focusNode: _passwordFocus,
                  obscureText: true,
                  textInputAction: TextInputAction.go,
                  style: TextStyle(color: MX.fg),
                  decoration: _plainInput('至少 8 位'),
                  onSubmitted: (_) => _submit(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _advancedToggle() {
    return TextButton(
      onPressed: () => setState(() => _advancedOpen = !_advancedOpen),
      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
      child: Row(
        children: [
          Icon(Icons.tune, size: 15, color: MX.dim),
          const SizedBox(width: 7),
          Text('高级连接选项', style: TextStyle(color: MX.dim, fontSize: 12, fontWeight: FontWeight.w500)),
          const Spacer(),
          Icon(_advancedOpen ? Icons.expand_less : Icons.expand_more, size: 18, color: MX.dim),
        ],
      ),
    );
  }

  Widget _advancedSection() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _inputLabel('代理 Cookie（NAS 反向代理鉴权）'),
          const SizedBox(height: 9),
          _inputBox(
            active: false,
            minHeight: 78,
            child: TextField(
              controller: _proxyCtrl,
              maxLines: 4,
              minLines: 2,
              autocorrect: false,
              style: TextStyle(color: MX.fg),
              decoration: _plainInput('name=value; name2=value2'),
            ),
          ),
          const SizedBox(height: 8),
          Text('仅当 NAS 反向代理要求 Cookie 鉴权时填写；一般无需配置。',
              style: TextStyle(color: MX.dim, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _errorMessage() {
    const errorColor = Color(0xFFE04350);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: errorColor.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: errorColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_error, style: const TextStyle(color: errorColor, fontSize: 12, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _submitButton(bool setup) {
    return SizedBox(
      width: double.infinity,
      height: 40,
      child: FilledButton(
        onPressed: _loading ? null : _submit,
        style: FilledButton.styleFrom(backgroundColor: MX.ember, foregroundColor: Colors.white),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_loading)
              const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            else
              const Icon(Icons.arrow_forward, size: 18),
            const SizedBox(width: 8),
            Text(_loading ? '正在连接…' : setup ? '完成设置' : '进入 MusicX',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _inputLabel(String text) => Text(text,
      style: TextStyle(color: MX.fg.withOpacity(0.84), fontSize: 12, fontWeight: FontWeight.w600));

  InputDecoration _plainInput(String hint) => InputDecoration(
        isDense: true,
        border: InputBorder.none,
        hintText: hint,
        hintStyle: TextStyle(color: MX.dim),
      );

  Widget _inputBox({required bool active, required Widget child, double minHeight = 48}) {
    final accent = context.read<UIStore>().themeAccent;
    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: MX.fill,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: active ? accent.color.withOpacity(0.8) : MX.fillStrong,
          width: active ? 1.5 : 1,
        ),
      ),
      child: child,
    );
  }
}

/// Decorative gradient + glow background. Mirrors Swift `loginBackground`.
class _LoginBackground extends StatelessWidget {
  const _LoginBackground();

  @override
  Widget build(BuildContext context) {
    final accent = context.watch<UIStore>().themeAccent;
    return IgnorePointer(
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.fromRGBO(38, 20, 36, 1),
                    MX.heroBase,
                    Color.fromRGBO(13, 18, 31, 1),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: -120,
            top: -180,
            child: _glow(440, accent.color.withOpacity(0.34)),
          ),
          Positioned(
            left: -160,
            bottom: -140,
            child: _glow(420, const Color.fromRGBO(79, 92, 214, 0.26)),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color.fromRGBO(12, 10, 14, 0.4), Color.fromRGBO(12, 10, 14, 0.85)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glow(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: color, blurRadius: 110, spreadRadius: 60)],
          color: color,
        ),
      );
}
