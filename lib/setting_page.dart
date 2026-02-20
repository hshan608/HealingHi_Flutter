import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'dart:io';
import 'nickname_generator.dart';

// Supabase 클라이언트 전역 변수
final supabase = Supabase.instance.client;

// 마이페이지 화면
class MyPageScreen extends StatefulWidget {
  const MyPageScreen({super.key});

  @override
  State<MyPageScreen> createState() => _MyPageScreenState();
}

class _MyPageScreenState extends State<MyPageScreen> {
  final TextEditingController _nameController = TextEditingController();

  // 사용자 데이터
  String _profileImageUrl = '';
  String _name = '';
  String _selectedLanguage = 'kor'; // 기본값: 한국어
  int _shareCount = 0;
  String? _deviceId;
  bool _isLoading = true;
  bool _nicknameSaved = false; // 닉네임 저장 성공 상태

  // 공유 등급 계산
  String get _shareLevel {
    if (_shareCount >= 100) return '골드 / $_shareCount개';
    if (_shareCount >= 10) return '실버 / $_shareCount개';
    if (_shareCount >= 1) return '브론즈 / $_shareCount개';
    return '없음 / 0개';
  }

  int get _shareTierTarget {
    if (_shareCount >= 100) return 100;
    if (_shareCount >= 10) return 100;
    if (_shareCount >= 1) return 10;
    return 1;
  }

  int get _shareProgress {
    final target = _shareTierTarget;
    return ((_shareCount / target) * 100).clamp(0, 100).toInt();
  }

  // 언어 옵션
  final Map<String, String> _languageOptions = {'kor': '한국어', 'eng': '영어'};

  @override
  void initState() {
    super.initState();
    _getDeviceId();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // 디바이스 고유 ID 가져오기
  Future<void> _getDeviceId() async {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    String? deviceId;

    try {
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        deviceId = androidInfo.id; // Android ID
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        deviceId = iosInfo.identifierForVendor; // iOS Vendor ID
      } else if (Platform.isWindows) {
        WindowsDeviceInfo windowsInfo = await deviceInfo.windowsInfo;
        deviceId = windowsInfo.deviceId;
      } else if (Platform.isLinux) {
        LinuxDeviceInfo linuxInfo = await deviceInfo.linuxInfo;
        deviceId = linuxInfo.machineId;
      } else if (Platform.isMacOS) {
        MacOsDeviceInfo macOsInfo = await deviceInfo.macOsInfo;
        deviceId = macOsInfo.systemGUID;
      }

      setState(() {
        _deviceId = deviceId;
      });

      // 디바이스 ID를 가져온 후 사용자 정보 로드
      if (deviceId != null) {
        await _loadUserData();
      }
    } catch (e) {
      print('디바이스 ID 가져오기 실패: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Supabase에서 사용자 정보 불러오기
  Future<void> _loadUserData() async {
    if (_deviceId == null) return;

    try {
      // 공유 카운트 로드 (device_id 기반 - users 행 없이도 동작)
      final shareData = await supabase
          .from('device_shares')
          .select('share_count')
          .eq('device_id', _deviceId!)
          .maybeSingle();

      final shareCount = shareData != null
          ? (shareData['share_count'] ?? 0) as int
          : 0;

      final response = await supabase
          .from('users')
          .select()
          .eq('device_id', _deviceId!)
          .maybeSingle();

      if (response != null) {
        // 데이터가 있으면 불러오기
        setState(() {
          _name = response['user_id'] ?? '';
          _profileImageUrl = response['profile_image_url'] ?? '';
          _selectedLanguage = response['language'] ?? 'kor';
          _shareCount = shareCount;
          _nameController.text = _name;
          _isLoading = false;
        });
      } else {
        // 데이터가 없으면 랜덤 닉네임 표시
        setState(() {
          _nameController.text = '';
          _selectedLanguage = 'kor';
          _shareCount = shareCount;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('사용자 정보 로드 실패: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 언어 변경 및 저장
  Future<void> _updateLanguage(String languageCode) async {
    if (_deviceId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('디바이스 정보를 가져오는 중입니다. 잠시 후 다시 시도해주세요')),
      );
      return;
    }

    try {
      // Supabase에 언어 업데이트
      await supabase.from('users').upsert({
        'device_id': _deviceId,
        'user_id': _nameController.text.trim().isNotEmpty
            ? _nameController.text.trim()
            : _name,
        'language': languageCode,
        'profile_image_url': _profileImageUrl.isNotEmpty
            ? _profileImageUrl
            : null,
      }, onConflict: 'device_id').select();

      setState(() {
        _selectedLanguage = languageCode;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('언어가 ${_languageOptions[languageCode]}(으)로 변경되었습니다'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('언어 변경 실패: $e')));
      }
      print('언어 업데이트 오류: $e');
    }
  }

  // 이미지 선택 및 업로드
  Future<void> _pickAndUploadImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
      );

      if (image == null) return;

      // 이미지 크롭 (원형 프로필 스타일)
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: image.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        maxWidth: 512,
        maxHeight: 512,
        compressQuality: 75,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: '프로필 사진',
            toolbarColor: Colors.white,
            toolbarWidgetColor: Colors.black87,
            activeControlsWidgetColor: const Color(0xFF4CAF50),
            backgroundColor: Colors.black,
            cropStyle: CropStyle.circle,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
            hideBottomControls: true,
            showCropGrid: false,
          ),
          IOSUiSettings(
            title: '프로필 사진',
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
            rotateButtonsHidden: true,
            rotateClockwiseButtonHidden: true,
            aspectRatioPickerButtonHidden: true,
          ),
        ],
      );

      if (croppedFile == null) return;

      if (_deviceId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('디바이스 정보를 가져오는 중입니다. 잠시 후 다시 시도해주세요')),
          );
        }
        return;
      }

      // 로딩 표시
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('이미지 업로드 중...')));
      }

      // 파일 읽기
      final bytes = await File(croppedFile.path).readAsBytes();
      final fileExt = croppedFile.path.split('.').last;
      final fileName = '$_deviceId.$fileExt';
      final filePath = 'profiles/$fileName';

      // Supabase Storage에 업로드
      await supabase.storage
          .from('avatars')
          .uploadBinary(
            filePath,
            bytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: 'image/$fileExt',
            ),
          );

      // Public URL 가져오기
      final imageUrl = supabase.storage.from('avatars').getPublicUrl(filePath);

      // users 테이블 업데이트 (device_id를 기준으로 upsert)
      await supabase.from('users').upsert({
        'device_id': _deviceId,
        'user_id': _nameController.text.trim(),
        'profile_image_url': imageUrl,
        'language': _selectedLanguage,
      }, onConflict: 'device_id').select();

      setState(() {
        _profileImageUrl = imageUrl;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('프로필 사진이 업데이트되었습니다!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('이미지 업로드 실패: $e')));
      }
      print('이미지 업로드 오류: $e');
    }
  }

  // Supabase에 사용자 정보 저장
  Future<void> _saveUserToSupabase() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('닉네임을 입력해주세요')));
      return;
    }

    if (_deviceId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('디바이스 정보를 가져오는 중입니다. 잠시 후 다시 시도해주세요')),
      );
      return;
    }

    try {
      final newName = _nameController.text.trim();

      // 닉네임 중복 확인 (자신의 device_id 제외)
      final existing = await supabase
          .from('users')
          .select('device_id')
          .eq('user_id', newName)
          .neq('device_id', _deviceId!)
          .maybeSingle();

      if (existing != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('중복된 닉네임입니다.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Supabase users 테이블에 데이터 저장
      await supabase.from('users').upsert({
        'device_id': _deviceId,
        'user_id': newName,
        'profile_image_url': _profileImageUrl.isNotEmpty
            ? _profileImageUrl
            : null,
        'language': _selectedLanguage,
      }, onConflict: 'device_id').select();

      setState(() {
        _name = newName;
        _nicknameSaved = true;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('닉네임이 저장되었습니다.'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // 2초 후 체크박스를 다시 회색으로
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _nicknameSaved = false;
          });
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('저장 실패: $e')));
      }
      print('Supabase 저장 오류: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 로딩 중일 때
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F5F5),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                // 상단 제목
                const Row(
                  children: [
                    Text(
                      '프로필 설정',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 30),

                // 프로필 이미지와 월계관
                GestureDetector(
                  onTap: _pickAndUploadImage,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.2),
                          spreadRadius: 2,
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        // 프로필 이미지
                        Positioned.fill(
                          child: ClipOval(
                            child: _profileImageUrl.isNotEmpty
                                ? Image.network(
                                    _profileImageUrl,
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    color: Colors.grey[300],
                                    child: const Icon(
                                      Icons.person,
                                      size: 60,
                                      color: Colors.grey,
                                    ),
                                  ),
                          ),
                        ),
                        // 카메라 아이콘 (편집 힌트)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                        // 월계관 장식 이미지 사용 대신 아이콘만 표시
                        // const Positioned(
                        //   top: -10,
                        //   left: -10,
                        //   right: -10,
                        //   child: SizedBox(
                        //     height: 40,
                        //     child: Icon(
                        //       Icons.emoji_events,
                        //       color: Colors.amber,
                        //       size: 30,
                        //     ),
                        //   ),
                        // ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),

                // 이름 입력 필드 (공유 1회 이상이면 편집 가능)
                if (_shareCount >= 1)
                  _buildInputField(
                    label: '닉네임',
                    controller: _nameController,
                    hintText: '닉네임을 입력하세요',
                    hasCheckIcon: true,
                  )
                else
                  _buildReadOnlyNameField(
                    label: '닉네임',
                    value: _deviceId != null
                        ? generateNickname(_deviceId!)
                        : '로딩중...',
                  ),
                const SizedBox(height: 20),

                // 언어 선택 필드
                _buildLanguageSelector(),
                const SizedBox(height: 30),

                // 공유 등급/개 섹션
                _buildInfoSection(
                  title: '공유 등급/개',
                  value: _shareLevel,
                  valueColor: Colors.red,
                ),
                const SizedBox(height: 20),

                // 공유 달성도 섹션
                _buildAchievementSection(),

                // 명언 신청 버튼 (공유 10회 초과 시 표시)
                if (_shareCount > 1) ...[
                  const SizedBox(height: 30),
                  _buildQuoteRequestButton(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '언어',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 56, // 다른 입력 필드와 동일한 높이
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                spreadRadius: 1,
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: DropdownButtonHideUnderline(
            child: ButtonTheme(
              alignedDropdown: true,
              child: DropdownButton<String>(
                value: _selectedLanguage,
                isExpanded: true,
                borderRadius: BorderRadius.circular(25),
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
                icon: const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: Icon(Icons.arrow_drop_down, color: Colors.grey),
                ),
                items: _languageOptions.entries.map((entry) {
                  return DropdownMenuItem<String>(
                    value: entry.key,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(entry.value),
                    ),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null && newValue != _selectedLanguage) {
                    _updateLanguage(newValue);
                  }
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    required String hintText,
    required bool hasCheckIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                spreadRadius: 1,
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.done,
            enableInteractiveSelection: true,
            onTap: () {
              SystemChannels.textInput.invokeMethod('TextInput.show');
            },
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
              suffixIcon: hasCheckIcon
                  ? GestureDetector(
                      onTap: _saveUserToSupabase,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeInOut,
                        margin: const EdgeInsets.all(8),
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: _nicknameSaved ? Colors.green : Colors.grey[400],
                          shape: BoxShape.circle,
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder: (child, animation) {
                            return ScaleTransition(
                              scale: animation,
                              child: child,
                            );
                          },
                          child: Icon(
                            Icons.check,
                            key: ValueKey<bool>(_nicknameSaved),
                            color: Colors.white,
                            size: _nicknameSaved ? 20 : 16,
                          ),
                        ),
                      ),
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 16,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReadOnlyNameField({
    required String label,
    required String value,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                spreadRadius: 1,
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Text(
            '명언을 1회 이상 공유하면 닉네임을 설정할 수 있어요!',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoSection({
    required String title,
    required String value,
    Color? valueColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 16,
              height: 16,
              decoration: const BoxDecoration(
                color: Colors.grey,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.help, color: Colors.white, size: 12),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                spreadRadius: 1,
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: valueColor ?? Colors.black87,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuoteRequestButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: () => _showQuoteRequestForm(),
        icon: const Icon(Icons.edit_note, size: 22),
        label: const Text(
          '명언 신청',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF4CAF50),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
          elevation: 2,
        ),
      ),
    );
  }

  void _showQuoteRequestForm() {
    final quoteController = TextEditingController();
    final authorController = TextEditingController();
    final categoryController = TextEditingController();
    bool isSubmitted = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            if (isSubmitted) {
              return Container(
                padding: const EdgeInsets.all(32),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      color: Color(0xFF4CAF50),
                      size: 64,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '신청이 완료되었습니다!',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '관리자 검토 후 등록됩니다.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4CAF50),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ),
                        child: const Text('확인'),
                      ),
                    ),
                  ],
                ),
              );
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 핸들바
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 제목
                      const Text(
                        '명언 신청',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '등록하고 싶은 명언을 신청해주세요.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 명언 내용 입력
                      const Text(
                        '명언 내용 *',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: quoteController,
                        maxLines: 4,
                        maxLength: 300,
                        decoration: InputDecoration(
                          hintText: '명언을 입력해주세요',
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          filled: true,
                          fillColor: Colors.grey[50],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: Color(0xFF4CAF50)),
                          ),
                          contentPadding: const EdgeInsets.all(16),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 저자 입력
                      const Text(
                        '저자 (선택)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: authorController,
                        maxLength: 50,
                        decoration: InputDecoration(
                          hintText: '저자를 입력해주세요',
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          filled: true,
                          fillColor: Colors.grey[50],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: Color(0xFF4CAF50)),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 카테고리 입력
                      const Text(
                        '카테고리 (선택)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: categoryController,
                        maxLength: 30,
                        decoration: InputDecoration(
                          hintText: '예: 인생, 사랑, 성공, 우정',
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          filled: true,
                          fillColor: Colors.grey[50],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: Color(0xFF4CAF50)),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 신청 버튼
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () {
                            if (quoteController.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('명언 내용을 입력해주세요'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              return;
                            }
                            setModalState(() {
                              isSubmitted = true;
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4CAF50),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                            ),
                            elevation: 2,
                          ),
                          child: const Text(
                            '신청하기',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAchievementSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Text(
              '공유 달성도',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
            SizedBox(width: 8),
            Icon(Icons.help_outline, color: Colors.grey, size: 16),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                spreadRadius: 1,
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 진행률 표시
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$_shareCount/$_shareTierTarget',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    '$_shareProgress%',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 진행바
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: _shareProgress,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    Expanded(flex: 100 - _shareProgress, child: Container()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
