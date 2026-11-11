import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Resilient App',
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    home: const HomePage(),
  );
}

// ---------------------------------------------------------------------------
// Simulated server (4 modes from the lab)
// ---------------------------------------------------------------------------
enum ServerMode { normal, slow, flaky, hangs }

class FakeServer {
  int _flakyCalls = 0;
  void reset() => _flakyCalls = 0;

  Future<http.Response> get(ServerMode mode) async {
    final body = jsonEncode([
      'Lecture 1: Intro',
      'Lecture 5: Local Storage',
      'Lecture 9: Unreliable Networks',
    ]);
    switch (mode) {
      case ServerMode.normal:
        return http.Response(body, 200);
      case ServerMode.slow:
        await Future.delayed(const Duration(seconds: 2));
        return http.Response(body, 200);
      case ServerMode.flaky:
        _flakyCalls++;
        if (_flakyCalls <= 2) return http.Response('Service Unavailable', 503);
        return http.Response(body, 200);
      case ServerMode.hangs:
        await Future.delayed(const Duration(seconds: 60)); // never answers in time
        return http.Response(body, 200);
    }
  }
}

// ---------------------------------------------------------------------------
// Errors -> human messages
// ---------------------------------------------------------------------------
class NetError implements Exception {
  final String message;
  final bool offline;
  NetError(this.message, {this.offline = false});
}

NetError mapError(Object e) {
  if (e is NetError) return e;
  if (e is TimeoutException) return NetError('The server is taking too long.');
  if (e is SocketException || e is http.ClientException) {
    return NetError("Can't reach the server.");
  }
  return NetError('Something went wrong. Please try again.');
}

// ---------------------------------------------------------------------------
// UI
// ---------------------------------------------------------------------------
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const maxAttempts = 3;
  static const timeout = Duration(seconds: 5);

  final _server = FakeServer();
  ServerMode _mode = ServerMode.normal;

  bool _loading = false;
  bool _stillWorking = false;
  bool _offline = false;
  String? _status; // "Retrying in 2s (attempt 3 of 3)..."
  String? _error;
  List<String> _data = []; // kept on screen even after a failure
  bool _errorWasOffline = false;

  Timer? _slowTimer;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  @override
  void initState() {
    super.initState();
    Connectivity().checkConnectivity().then(_updateConnectivity);
    _sub = Connectivity().onConnectivityChanged.listen((r) {
      final wasOffline = _offline;
      _updateConnectivity(r);
      // Network came back -> retry by itself
      if (wasOffline && !_offline && _errorWasOffline && !_loading) _load();
    });
  }

  void _updateConnectivity(List<ConnectivityResult> r) {
    final off = r.isEmpty || r.every((c) => c == ConnectivityResult.none);
    if (mounted) setState(() => _offline = off);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _slowTimer?.cancel();
    super.dispose();
  }

  Future<bool> _isOffline() async {
    final r = await Connectivity().checkConnectivity();
    return r.isEmpty || r.every((c) => c == ConnectivityResult.none);
  }

  Future<List<String>> _fetchWithRetry() async {
    NetError last = NetError('Unknown error');
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      // 1) connectivity check: 'none' is a reliable offline signal
      if (await _isOffline()) {
        throw NetError(
            "You're offline. Turn off airplane mode and try again.",
            offline: true);
      }
      try {
        // 2) request with a timeout
        final res = await _server.get(_mode).timeout(timeout);
        if (res.statusCode >= 200 && res.statusCode < 300) {
          return List<String>.from(jsonDecode(res.body));
        }
        if (res.statusCode == 401) {
          throw NetError('Please log in again.'); // do not retry
        }
        if (res.statusCode >= 400 && res.statusCode < 500) {
          throw NetError('The request was rejected.'); // do not retry
        }
        last = NetError('The server had a problem. Try again later.');
      } on NetError {
        rethrow; // 4xx -> stop immediately
      } catch (e) {
        last = mapError(e); // timeout / socket -> retryable
      }

      if (attempt == maxAttempts) break; // give up

      // 3) exponential backoff: 1s, 2s, 4s ...
      final wait = 1 << (attempt - 1);
      if (mounted) {
        setState(() => _status =
        'Retrying in ${wait}s (attempt ${attempt + 1} of $maxAttempts)...');
      }
      await Future.delayed(Duration(seconds: wait));
    }
    throw last;
  }

  Future<void> _load() async {
    if (_loading) return;
    _server.reset();
    setState(() {
      _loading = true;
      _stillWorking = false;
      _error = null;
      _status = null;
    });
    // After a few seconds say it is slow, not dead
    _slowTimer?.cancel();
    _slowTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _loading) setState(() => _stillWorking = true);
    });

    try {
      final items = await _fetchWithRetry();
      if (!mounted) return;
      setState(() {
        _data = items;
        _errorWasOffline = false;
      });
    } catch (e) {
      final err = mapError(e);
      if (!mounted) return;
      setState(() {
        _error = err.message;
        _errorWasOffline = err.offline;
      });
    } finally {
      _slowTimer?.cancel();
      if (mounted) {
        setState(() {
          _loading = false;
          _stillWorking = false;
          _status = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Resilient App')),
      body: Column(
        children: [
          if (_offline)
            Container(
              width: double.infinity,
              color: cs.errorContainer,
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                Icon(Icons.wifi_off, color: cs.onErrorContainer),
                const SizedBox(width: 8),
                Text("You're offline",
                    style: TextStyle(color: cs.onErrorContainer)),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const Text('Server mode: '),
              const SizedBox(width: 8),
              DropdownButton<ServerMode>(
                value: _mode,
                onChanged: _loading
                    ? null
                    : (m) => setState(() => _mode = m!),
                items: [
                  for (final m in ServerMode.values)
                    DropdownMenuItem(value: m, child: Text(m.name)),
                ],
              ),
              const Spacer(),
              FilledButton(
                  onPressed: _loading ? null : _load, child: const Text('Load')),
            ]),
          ),
          if (_loading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(_status ??
                        (_stillWorking ? 'Still working...' : 'Loading...'))),
              ]),
            ),
          if (_error != null)
            Card(
              color: cs.errorContainer,
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(
                      child: Text(_error!,
                          style: TextStyle(color: cs.onErrorContainer))),
                  TextButton(onPressed: _load, child: const Text('Try again')),
                ]),
              ),
            ),
          if (_error != null && _data.isNotEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Showing earlier data:',
                      style: TextStyle(fontStyle: FontStyle.italic))),
            ),
          Expanded(
            child: ListView(
              children: [for (final s in _data) ListTile(title: Text(s))],
            ),
          ),
        ],
      ),
    );
  }
}