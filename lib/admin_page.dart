import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  // Static: survives widget rebuilds, resets when app process is killed
  static bool _isAuthenticated = false;

  final _passwordController = TextEditingController();
  bool _passwordObscured = true;
  bool _passwordError = false;

  List<Map<String, dynamic>> _pendingQuotes = [];
  Map<String, String> _applicantNames = {}; // device_id -> user_id
  bool _isLoading = false;

  static const String _adminPassword = '03220608';

  @override
  void initState() {
    super.initState();
    if (_isAuthenticated) {
      _loadPendingQuotes();
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadPendingQuotes() async {
    setState(() => _isLoading = true);
    try {
      final response = await supabase
          .from('request_quotes')
          .select()
          .isFilter('is_accept', null)
          .order('created_at', ascending: true);

      final quotes = List<Map<String, dynamic>>.from(response);

      // device_id 목록 수집 후 users 테이블에서 user_id 조회
      final deviceIds = quotes
          .map((q) => q['device_id']?.toString())
          .where((id) => id != null && id.isNotEmpty)
          .toSet()
          .cast<String>()
          .toList();

      final Map<String, String> nameMap = {};
      if (deviceIds.isNotEmpty) {
        final users = await supabase
            .from('users')
            .select('device_id, user_id')
            .inFilter('device_id', deviceIds);

        for (final user in users as List) {
          final did = user['device_id']?.toString();
          final uid = user['user_id']?.toString();
          if (did != null && uid != null) {
            nameMap[did] = uid;
          }
        }
      }

      if (mounted) {
        setState(() {
          _pendingQuotes = quotes;
          _applicantNames = nameMap;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로드 실패: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _checkPassword() {
    if (_passwordController.text == _adminPassword) {
      setState(() {
        _isAuthenticated = true;
        _passwordError = false;
      });
      _loadPendingQuotes();
    } else {
      setState(() {
        _passwordError = true;
      });
    }
  }

  Future<void> _approveQuote(Map<String, dynamic> quote) async {
    final rowId = quote['id'].toString();
    final newQuoteId = 'req_$rowId';

    try {
      await supabase.from('quotes').insert({
        'id': newQuoteId,
        'text_kr': quote['text_kr'],
        'text_eng': quote['text_eng'],
        'resoner_kr': quote['resoner_kr'],
        'resoner_eng': quote['resoner_eng'],
        'tag_kr': quote['tag_kr'],
        'tag_eng': quote['tag_eng'],
        'imagefile': quote['imagefile'],
      });

      await supabase
          .from('request_quotes')
          .update({'is_accept': 1})
          .eq('id', int.parse(rowId));

      if (mounted) {
        setState(() {
          _pendingQuotes.removeWhere((q) => q['id'].toString() == rowId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('승인되었습니다'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('승인 실패: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _rejectQuote(Map<String, dynamic> quote) async {
    final rowId = quote['id'].toString();

    try {
      await supabase
          .from('request_quotes')
          .update({'is_accept': 0})
          .eq('id', int.parse(rowId));

      if (mounted) {
        setState(() {
          _pendingQuotes.removeWhere((q) => q['id'].toString() == rowId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('거절되었습니다')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('거절 실패: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F5F5),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isAuthenticated ? '명언 신청 관리' : '관리자 인증',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ),
      body: _isAuthenticated ? _buildAdminList() : _buildPasswordGate(),
    );
  }

  Widget _buildPasswordGate() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 24),
            TextField(
              controller: _passwordController,
              obscureText: _passwordObscured,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: '비밀번호를 입력하세요',
                errorText: _passwordError ? '비밀번호가 올바르지 않습니다' : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _passwordObscured ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () {
                    setState(() {
                      _passwordObscured = !_passwordObscured;
                    });
                  },
                ),
              ),
              onSubmitted: (_) => _checkPassword(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _checkPassword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF81A684),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
                child: const Text(
                  '확인',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_pendingQuotes.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              '대기 중인 신청이 없습니다',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPendingQuotes,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _pendingQuotes.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          return _buildQuoteCard(_pendingQuotes[index]);
        },
      ),
    );
  }

  Widget _buildQuoteCard(Map<String, dynamic> quote) {
    final rowId = quote['id'].toString();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF81A684).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  quote['tag_kr'] ?? '',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF81A684),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                'ID: $rowId',
                style: TextStyle(fontSize: 11, color: Colors.grey[400]),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            quote['text_kr'] ?? '',
            style: const TextStyle(
              fontSize: 15,
              color: Colors.black87,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '- ${quote['resoner_kr'] ?? ''}',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '신청자: ${_applicantNames[quote['device_id']?.toString()] ?? quote['device_id'] ?? '알 수 없음'}',
            style: TextStyle(fontSize: 11, color: Colors.grey[400]),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _rejectQuote(quote),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('거절'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _approveQuote(quote),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF81A684),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('승인'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
