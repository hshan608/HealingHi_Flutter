import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'dart:convert';

// Supabase 클라이언트 전역 변수
final supabase = Supabase.instance.client;

// 메인 화면
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _quotes = [];
  bool _isLoading = true;
  String? _deviceId;
  int? _userIdx;
  bool _isSavingLike = false;
  Set<String> _savedQuoteIds = {};
  Map<String, String> _resonerImages = {}; // quoteId -> imagePath 매핑

  @override
  void initState() {
    super.initState();
    _loadResonerImages();
    _loadQuotes();
    _initUserIdentity();
  }

  // assets/resoner/ 폴더의 이미지 목록 로드
  Future<void> _loadResonerImages() async {
    try {
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent);

      final resonerFiles = manifestMap.keys
          .where((path) => path.startsWith('assets/resoner/'))
          .toList();

      final Map<String, String> imageMap = {};
      for (final path in resonerFiles) {
        // 파일명에서 id 추출 (예: assets/resoner/1_name.png -> 1)
        final fileName = path.split('/').last;
        final idMatch = RegExp(r'^(\d+)_').firstMatch(fileName);
        if (idMatch != null) {
          final id = idMatch.group(1)!;
          imageMap[id] = path;
        }
      }

      if (mounted) {
        setState(() {
          _resonerImages = imageMap;
        });
      }
    } catch (e) {
      print('Resoner 이미지 로드 실패: $e');
    }
  }

  // quoteId로 이미지 경로 가져오기
  String? _getResonerImagePath(String? quoteId) {
    if (quoteId == null) return null;
    return _resonerImages[quoteId];
  }

  // Supabase에서 명언 데이터 가져오기
  Future<void> _loadQuotes() async {
    try {
      final response = await supabase
          .from('quotes')
          .select()
          .order('created_at', ascending: false);

      setState(() {
        _quotes = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (error) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('데이터를 불러오는데 실패했습니다: $error')));
      }
    }
  }

  // 디바이스 ID와 사용자 idx 로드
  Future<void> _initUserIdentity() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      String? deviceId;

      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        deviceId = info.id;
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        deviceId = info.identifierForVendor;
      } else if (Platform.isWindows) {
        final info = await deviceInfo.windowsInfo;
        deviceId = info.deviceId;
      } else if (Platform.isLinux) {
        final info = await deviceInfo.linuxInfo;
        deviceId = info.machineId;
      } else if (Platform.isMacOS) {
        final info = await deviceInfo.macOsInfo;
        deviceId = info.systemGUID;
      }

      _deviceId = deviceId;

      if (deviceId == null) return;

      final user = await supabase
          .from('users')
          .select('idx')
          .eq('device_id', deviceId)
          .maybeSingle();

      if (user != null && mounted) {
        setState(() {
          _userIdx = _toInt(user['idx']);
        });
        await _loadSavedQuoteIds();
      }
    } catch (e) {
      // 디바이스 정보를 가져오지 못해도 앱 동작에는 영향 없음
      print('사용자 식별자 로드 실패: $e');
    }
  }

  Future<void> _loadSavedQuoteIds() async {
    if (_userIdx == null) return;
    try {
      final userQuotes = await supabase
          .from('users_quotes')
          .select('quotes_id')
          .eq('user_idx', _userIdx!);

      final ids = userQuotes
          .map<String?>((row) => row['quotes_id']?.toString())
          .where((id) => id != null && id.isNotEmpty)
          .cast<String>()
          .toSet();

      if (mounted) {
        setState(() {
          _savedQuoteIds = ids;
        });
      }
    } catch (e) {
      print('저장된 명언 ID 로드 실패: $e');
    }
  }

  Future<void> _toggleUserQuote(String? quoteId) async {
    if (quoteId == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('명언 ID를 찾을 수 없습니다.')));
      }
      return;
    }

    if (_isSavingLike) return;
    setState(() {
      _isSavingLike = true;
    });

    try {
      // 사용자 idx가 없으면 다시 시도
      if (_userIdx == null) {
        await _initUserIdentity();
      }

      if (_userIdx == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('사용자 정보를 불러오지 못했습니다. 프로필 저장 후 다시 시도해주세요.'),
            ),
          );
        }
        return;
      }

      final isSaved = _savedQuoteIds.contains(quoteId);

      if (isSaved) {
        // 이미 저장됨 → 삭제
        await supabase
            .from('users_quotes')
            .delete()
            .eq('user_idx', _userIdx!)
            .eq('quotes_id', quoteId);

        if (mounted) {
          setState(() {
            _savedQuoteIds.remove(quoteId);
          });
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('보관함에서 삭제되었습니다.')));
        }
      } else {
        // 저장 안됨 → 추가
        await supabase.from('users_quotes').upsert({
          'user_idx': _userIdx,
          'quotes_id': quoteId,
        }, onConflict: 'user_idx,quotes_id');

        if (mounted) {
          setState(() {
            _savedQuoteIds.add(quoteId);
          });
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('보관함에 저장되었습니다.')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('저장 중 오류가 발생했습니다: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingLike = false;
        });
      }
    }
  }

  String? _extractQuoteId(Map<String, dynamic> quote) {
    final value = quote['id'] ?? quote['idx'];
    if (value == null) return null;
    return value.toString();
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  // 공유하기 함수
  void _shareContent(String title, String content) async {
    try {
      await Share.share(
        '$title\n\n$content\n\n공유됨 - Healing Hi 앱',
        subject: title,
      );
    } catch (e) {
      // 공유 기능이 실패하면 클립보드에 복사
      await Clipboard.setData(
        ClipboardData(text: '$title\n\n$content\n\n공유됨 - Healing Hi 앱'),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('내용이 클립보드에 복사되었습니다!')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFDDE7DE),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 박스 리스트
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _quotes.isEmpty
                    ? const Center(
                        child: Text(
                          '명언이 없습니다.\n데이터베이스를 확인해주세요.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadQuotes,
                        child: ListView.builder(
                          padding: const EdgeInsets.only(top: 20.0),
                          itemCount: _quotes.length,
                          itemBuilder: (context, index) {
                            final quote = _quotes[index];
                            final quoteId = _extractQuoteId(quote);
                            return _buildContentBox(
                              '${quote['resoner_kr']}',
                              quote['text_kr'],
                              quoteId,
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContentBox(String title, String content, String? quoteId) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16.0),
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 28.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.0),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 원형 프로필 이미지
          ClipOval(
            child: Container(
              width: 70,
              height: 70,
              color: Colors.grey[200],
              child: _getResonerImagePath(quoteId) != null
                  ? Image.asset(
                      _getResonerImagePath(quoteId)!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(Icons.person, size: 40, color: Colors.grey[400]);
                      },
                    )
                  : Icon(Icons.person, size: 40, color: Colors.grey[400]),
            ),
          ),
          const SizedBox(height: 20),
          // 명언 텍스트 (중앙 정렬, 이탤릭)
          Text(
            content,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontStyle: FontStyle.italic,
              color: Colors.grey[800],
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),
          // 저자명 (대문자 스타일)
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey[500],
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          // 버튼 영역
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () {
                  _toggleUserQuote(quoteId);
                },
                icon: Image.asset(
                  quoteId != null && _savedQuoteIds.contains(quoteId)
                      ? 'assets/heart2.png'
                      : 'assets/heart1.png',
                  width: 24,
                  height: 24,
                ),
                tooltip: '좋아요',
              ),
              IconButton(
                onPressed: () {
                  _shareContent(title, content);
                },
                icon: const Icon(Icons.share),
                iconSize: 20,
                color: Colors.grey[600],
                tooltip: '공유하기',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
