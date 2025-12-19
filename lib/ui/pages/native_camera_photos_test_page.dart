import 'package:flutter/material.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/utils/file_size_formatter.dart';
import 'package:flutter/services.dart';

/// 本机相机拍照统计测试页面
/// 
/// 通过读取照片的 EXIF 信息（TAG_MAKE, TAG_MODEL）判断是否为本机拍摄
class NativeCameraPhotosTestPage extends StatefulWidget {
  const NativeCameraPhotosTestPage({super.key});

  @override
  State<NativeCameraPhotosTestPage> createState() => _NativeCameraPhotosTestPageState();
}

class _NativeCameraPhotosTestPageState extends State<NativeCameraPhotosTestPage> {
  static const _channel = MethodChannel('easyfile/native_camera_test');
  
  bool _isScanning = false;
  String _scanMode = 'exif';  // 'exif' 或 'package'
  String _mediaType = 'photo'; // 'photo' 或 'video'
  
  // 扫描结果
  List<Map<String, dynamic>>? _results;
  int? _scanDuration;
  String? _cameraPackageName;  // 系统相机包名
  
  // 设备信息
  String? _deviceMake;
  String? _deviceModel;
  
  // 统计信息
  int _totalPhotos = 0;
  int _nativePhotos = 0;
  int _totalSize = 0;
  int _nativeSize = 0;
  int _cameraPhotos = 0;      // Camera目录照片数
  int _cameraSize = 0;        // Camera目录占用空间
  int _picturesPhotos = 0;    // Pictures目录照片数
  int _picturesSize = 0;      // Pictures目录占用空间
  int _otherPhotos = 0;       // 其他目录照片数
  int _otherSize = 0;         // 其他目录占用空间

  @override
  void initState() {
    super.initState();
    _loadDeviceInfo();
  }

  /// 加载设备信息
  Future<void> _loadDeviceInfo() async {
    try {
      final Map<dynamic, dynamic> result = await _channel.invokeMethod('getDeviceInfo');
      setState(() {
        _deviceMake = result['make'] as String?;
        _deviceModel = result['model'] as String?;
      });
      logger.i('设备信息: $_deviceMake $_deviceModel');
    } catch (e) {
      logger.e('获取设备信息失败: $e');
    }
  }

  /// 执行扫描
  Future<void> _scan() async {
    setState(() {
      _isScanning = true;
      _results = null;
      _scanDuration = null;
      _cameraPackageName = null;
      _totalPhotos = 0;
      _nativePhotos = 0;
      _totalSize = 0;
      _nativeSize = 0;
      _cameraPhotos = 0;
      _cameraSize = 0;
      _picturesPhotos = 0;
      _picturesSize = 0;
      _otherPhotos = 0;
      _otherSize = 0;
    });

    if (_scanMode == 'package') {
      await _scanByPackage();
    } else {
      await _scanByExif();
    }
  }
  
  /// 通过 EXIF 扫描
  Future<void> _scanByExif() async {
    logger.i('开始扫描设备所有图片...');
    
    final startTime = DateTime.now();
    
    try {
      // 调用原生方法扫描并分析照片
      final List<dynamic> result = await _channel.invokeMethod('scanNativeCameraPhotos');
      
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime).inMilliseconds;

      // 处理结果
      final photos = result.map((item) => Map<String, dynamic>.from(item as Map)).toList();
      
      _processResults(photos, duration);
      
      logger.i('扫描完成: 总数 $_totalPhotos, 本机 $_nativePhotos, Camera $_cameraPhotos, Pictures $_picturesPhotos, 其他 $_otherPhotos, 耗时 ${duration}ms');
    } catch (e) {
      logger.e('扫描失败: $e');
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('扫描失败: $e')),
        );
      }
    }
  }
  
  /// 通过系统相机包名扫描
  Future<void> _scanByPackage() async {
    logger.i('开始通过系统相机包名扫描${_mediaType == 'photo' ? '图片' : '视频'}...');
    
    final startTime = DateTime.now();
    
    try {
      // 调用原生方法扫描
      final methodName = _mediaType == 'photo' ? 'scanCameraPackagePhotos' : 'scanCameraPackageVideos';
      final List<dynamic> result = await _channel.invokeMethod(methodName);
      
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime).inMilliseconds;

      // 处理结果
      final items = result.map((item) => Map<String, dynamic>.from(item as Map)).toList();
      
      // 提取相机包名
      if (items.isNotEmpty) {
        _cameraPackageName = items.first['ownerPackage'] as String?;
      }
      
      _processPackageResults(items, duration);
      
      logger.i('扫描完成: 总数 ${items.length}, 耗时 ${duration}ms');
    } catch (e) {
      logger.e('扫描失败: $e');
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('扫描失败: $e')),
        );
      }
    }
  }
  
  /// 处理 EXIF 扫描结果
  void _processResults(List<Map<String, dynamic>> photos, int duration) {
    // 统计信息
    int totalPhotos = photos.length;
    int nativePhotos = photos.where((p) => p['isNative'] == true).length;
    int totalSize = photos.fold(0, (sum, p) => sum + (p['size'] as int));
    int nativeSize = photos.where((p) => p['isNative'] == true)
        .fold(0, (sum, p) => sum + (p['size'] as int));
    
    // Camera目录统计（通过bucket或path判断）
    int cameraPhotos = photos.where((p) {
      final bucket = p['bucket'] as String? ?? '';
      final path = p['path'] as String;
      return bucket.toLowerCase() == 'camera' || path.contains('/DCIM/Camera');
    }).length;
    int cameraSize = photos.where((p) {
      final bucket = p['bucket'] as String? ?? '';
      final path = p['path'] as String;
      return bucket.toLowerCase() == 'camera' || path.contains('/DCIM/Camera');
    }).fold(0, (sum, p) => sum + (p['size'] as int));
    
    // Pictures目录统计
    int picturesPhotos = photos.where((p) => (p['path'] as String).contains('/Pictures/')).length;
    int picturesSize = photos.where((p) => (p['path'] as String).contains('/Pictures/'))
        .fold(0, (sum, p) => sum + (p['size'] as int));
    
    // 其他目录统计
    int otherPhotos = photos.where((p) {
      final bucket = p['bucket'] as String? ?? '';
      final path = p['path'] as String;
      final isCamera = bucket.toLowerCase() == 'camera' || path.contains('/DCIM/Camera');
      final isPictures = path.contains('/Pictures/');
      return !isCamera && !isPictures;
    }).length;
    int otherSize = photos.where((p) {
      final bucket = p['bucket'] as String? ?? '';
      final path = p['path'] as String;
      final isCamera = bucket.toLowerCase() == 'camera' || path.contains('/DCIM/Camera');
      final isPictures = path.contains('/Pictures/');
      return !isCamera && !isPictures;
    }).fold(0, (sum, p) => sum + (p['size'] as int));

    setState(() {
      _results = photos;
      _scanDuration = duration;
      _totalPhotos = totalPhotos;
      _nativePhotos = nativePhotos;
      _totalSize = totalSize;
      _nativeSize = nativeSize;
      _cameraPhotos = cameraPhotos;
      _cameraSize = cameraSize;
      _picturesPhotos = picturesPhotos;
      _picturesSize = picturesSize;
      _otherPhotos = otherPhotos;
      _otherSize = otherSize;
      _isScanning = false;
    });
  }
  
  /// 处理包名扫描结果
  void _processPackageResults(List<Map<String, dynamic>> photos, int duration) {
    int totalPhotos = photos.length;
    int totalSize = photos.fold(0, (sum, p) => sum + (p['size'] as int));
    
    // Camera目录统计
    int cameraPhotos = photos.where((p) {
      final bucket = p['bucket'] as String? ?? '';
      final path = p['path'] as String;
      return bucket.toLowerCase() == 'camera' || path.contains('/DCIM/Camera');
    }).length;
    int cameraSize = photos.where((p) {
      final bucket = p['bucket'] as String? ?? '';
      final path = p['path'] as String;
      return bucket.toLowerCase() == 'camera' || path.contains('/DCIM/Camera');
    }).fold(0, (sum, p) => sum + (p['size'] as int));
    
    // Pictures目录统计
    int picturesPhotos = photos.where((p) => (p['path'] as String).contains('/Pictures/')).length;
    int picturesSize = photos.where((p) => (p['path'] as String).contains('/Pictures/'))
        .fold(0, (sum, p) => sum + (p['size'] as int));
    
    // 其他目录统计
    int otherPhotos = photos.where((p) {
      final bucket = p['bucket'] as String? ?? '';
      final path = p['path'] as String;
      final isCamera = bucket.toLowerCase() == 'camera' || path.contains('/DCIM/Camera');
      final isPictures = path.contains('/Pictures/');
      return !isCamera && !isPictures;
    }).length;
    int otherSize = photos.where((p) {
      final bucket = p['bucket'] as String? ?? '';
      final path = p['path'] as String;
      final isCamera = bucket.toLowerCase() == 'camera' || path.contains('/DCIM/Camera');
      final isPictures = path.contains('/Pictures/');
      return !isCamera && !isPictures;
    }).fold(0, (sum, p) => sum + (p['size'] as int));

    setState(() {
      _results = photos;
      _scanDuration = duration;
      _totalPhotos = totalPhotos;
      _nativePhotos = totalPhotos;  // 包名方式全部认为是本机拍摄
      _totalSize = totalSize;
      _nativeSize = totalSize;
      _cameraPhotos = cameraPhotos;
      _cameraSize = cameraSize;
      _picturesPhotos = picturesPhotos;
      _picturesSize = picturesSize;
      _otherPhotos = otherPhotos;
      _otherSize = otherSize;
      _isScanning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('本机相机${_mediaType == 'photo' ? '拍照' : '录像'}统计'),
        actions: [
          // 媒体类型切换
          PopupMenuButton<String>(
            icon: Icon(_mediaType == 'photo' ? Icons.photo : Icons.videocam),
            initialValue: _mediaType,
            onSelected: (value) {
              setState(() {
                _mediaType = value;
                _results = null;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'photo',
                child: Row(
                  children: [
                    Icon(Icons.photo),
                    SizedBox(width: 8),
                    Text('照片'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'video',
                child: Row(
                  children: [
                    Icon(Icons.videocam),
                    SizedBox(width: 8),
                    Text('视频'),
                  ],
                ),
              ),
            ],
          ),
          // 扫描模式切换
          PopupMenuButton<String>(
            icon: const Icon(Icons.settings),
            initialValue: _scanMode,
            onSelected: (value) {
              setState(() {
                _scanMode = value;
                _results = null;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'exif',
                child: Text('EXIF模式（准确但慢）'),
              ),
              const PopupMenuItem(
                value: 'package',
                child: Text('包名模式（快速）'),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isScanning ? null : _scan,
            tooltip: '开始扫描',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 设备信息卡片
        _buildDeviceInfoCard(),
        const SizedBox(height: 16),
        
        // 扫描按钮
        if (!_isScanning && _results == null)
          _buildStartButton(),
        
        // 加载中
        if (_isScanning)
          _buildLoadingView(),
        
        // 统计结果
        if (_results != null && !_isScanning) ...[
          _buildStatsCard(),
          const SizedBox(height: 16),
          _buildPhotosList(),
        ],
      ],
    );
  }

  /// 设备信息卡片
  Widget _buildDeviceInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.phone_android, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '设备信息',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildInfoRow('品牌', _deviceMake ?? '加载中...'),
            const SizedBox(height: 8),
            _buildInfoRow('型号', _deviceModel ?? '加载中...'),
            const SizedBox(height: 8),
            _buildInfoRow('媒体类型', _mediaType == 'photo' ? '照片' : '视频'),
            const SizedBox(height: 8),
            _buildInfoRow('扫描模式', _scanMode == 'exif' ? 'EXIF模式（准确）' : '包名模式（快速）'),
            if (_cameraPackageName != null) ...[
              const SizedBox(height: 8),
              _buildInfoRow('相机包名', _cameraPackageName!),
            ],
            const SizedBox(height: 12),
            Text(
              _scanMode == 'exif' 
                ? '通过 EXIF 信息判断是否为本机拍摄（准确但较慢）'
                : '通过系统相机包名快速过滤（速度快，只包含相机应用创建的${_mediaType == 'photo' ? '图片' : '视频'}）',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(
            '$label:',
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  /// 开始扫描按钮
  Widget _buildStartButton() {
    final mediaLabel = _mediaType == 'photo' ? '图片' : '视频';
    return Center(
      child: FilledButton.icon(
        onPressed: _scan,
        icon: Icon(_scanMode == 'exif' ? Icons.image_search : Icons.flash_on),
        label: Text(_scanMode == 'exif' ? '开始扫描$mediaLabel（EXIF）' : '快速扫描$mediaLabel（包名）'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        ),
      ),
    );
  }

  /// 加载中视图
  Widget _buildLoadingView() {
    final mediaLabel = _mediaType == 'photo' ? '图片' : '视频';
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(
            '正在扫描设备所有$mediaLabel...',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            _scanMode == 'exif' 
              ? '正在读取 EXIF 信息并分析（可能需要较长时间）'
              : '正在通过相机包名快速过滤...',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// 统计结果卡片
  Widget _buildStatsCard() {
    final nativePercentage = _totalPhotos > 0 
        ? (_nativePhotos / _totalPhotos * 100).toStringAsFixed(1)
        : '0.0';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '扫描结果',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (_scanDuration != null)
                  Chip(
                    label: Text('${_scanDuration}ms'),
                    avatar: const Icon(Icons.timer, size: 16),
                  ),
              ],
            ),
            const Divider(height: 24),
            
            // 照片数量统计
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    '总照片数',
                    _totalPhotos.toString(),
                    Icons.photo_library,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatItem(
                    '本机拍摄',
                    _nativePhotos.toString(),
                    Icons.camera_alt,
                    Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // 空间占用统计
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    '总空间',
                    FileSizeFormatter.formatBytes(_totalSize),
                    Icons.storage,
                    Colors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatItem(
                    '本机占用',
                    FileSizeFormatter.formatBytes(_nativeSize),
                    Icons.sd_storage,
                    Colors.purple,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // 目录分布标题
            Text(
              '目录分布',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            
            // Camera目录统计
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Camera照片',
                    _cameraPhotos.toString(),
                    Icons.camera,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatItem(
                    'Camera空间',
                    FileSizeFormatter.formatBytes(_cameraSize),
                    Icons.photo_camera,
                    Colors.lightBlue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Pictures目录统计
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Pictures照片',
                    _picturesPhotos.toString(),
                    Icons.folder_special,
                    Colors.teal,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatItem(
                    'Pictures空间',
                    FileSizeFormatter.formatBytes(_picturesSize),
                    Icons.folder,
                    Colors.cyan,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // 其他目录统计
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    '其他照片',
                    _otherPhotos.toString(),
                    Icons.photo_library,
                    Colors.deepOrange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatItem(
                    '其他空间',
                    FileSizeFormatter.formatBytes(_otherSize),
                    Icons.folder_open,
                    Colors.deepOrange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // 百分比进度条
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('本机拍摄占比'),
                    Text(
                      '$nativePercentage%',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: _totalPhotos > 0 ? _nativePhotos / _totalPhotos : 0,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: color.withOpacity(0.8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// 照片列表
  Widget _buildPhotosList() {
    if (_results == null || _results!.isEmpty) {
      return const SizedBox.shrink();
    }

    // 分组：本机 vs 其他
    final nativePhotos = _results!.where((p) => p['isNative'] == true).toList();
    final otherPhotos = _results!.where((p) => p['isNative'] != true).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '照片列表',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        
        // 本机拍摄
        if (nativePhotos.isNotEmpty) ...[
          _buildPhotoSection('本机拍摄 (${nativePhotos.length})', nativePhotos, true),
          const SizedBox(height: 16),
        ],
        
        // 其他照片
        if (otherPhotos.isNotEmpty) ...[
          _buildPhotoSection('其他照片 (${otherPhotos.length})', otherPhotos, false),
        ],
      ],
    );
  }

  Widget _buildPhotoSection(String title, List<Map<String, dynamic>> photos, bool isNative) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  isNative ? Icons.check_circle : Icons.info_outline,
                  color: isNative ? Colors.green : Colors.grey,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: photos.length > 10 ? 10 : photos.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
            itemBuilder: (context, index) {
              final photo = photos[index];
              return _buildPhotoItem(photo);
            },
          ),
          if (photos.length > 10)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Center(
                child: Text(
                  '还有 ${photos.length - 10} 张照片...',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPhotoItem(Map<String, dynamic> photo) {
    final name = photo['name'] as String;
    final size = photo['size'] as int;
    final make = photo['make'] as String?;
    final model = photo['model'] as String?;
    final date = photo['date'] as String?;
    final isNative = photo['isNative'] as bool? ?? false;

    return ListTile(
      leading: Icon(
        Icons.photo,
        color: isNative ? Colors.green : Colors.grey,
      ),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            FileSizeFormatter.formatBytes(size),
            style: const TextStyle(fontSize: 12),
          ),
          if (make != null || model != null)
            Text(
              '${make ?? ""}${make != null && model != null ? " " : ""}${model ?? ""}',
              style: TextStyle(
                fontSize: 11,
                color: isNative ? Colors.green : Colors.orange,
              ),
            ),
          if (date != null)
            Text(
              date,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
        ],
      ),
      dense: true,
    );
  }
}
