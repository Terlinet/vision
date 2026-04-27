import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    _cameras = await availableCameras();
  } catch (e) {
    print('Câmeras não detectadas: $e');
    _cameras = [];
  }
  runApp(const TerlineTVisionApp());
}

class TerlineTVisionApp extends StatelessWidget {
  const TerlineTVisionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TerlineT Vision',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.cyan, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const ObjectDetectionScreen(),
    );
  }
}

class ObjectDetectionScreen extends StatefulWidget {
  const ObjectDetectionScreen({super.key});

  @override
  State<ObjectDetectionScreen> createState() => _ObjectDetectionScreenState();
}

class _ObjectDetectionScreenState extends State<ObjectDetectionScreen> with TickerProviderStateMixin {
  int _selectedCameraIndex = 0;
  Uint8List? _imageBytes;
  List<dynamic> _results = [];
  String _description = "";
  bool _isLoading = false;
  bool _isRealTime = false;
  Timer? _timer;
  CameraController? _cameraController;
  final ImagePicker _picker = ImagePicker();
  final AudioPlayer _audioPlayer = AudioPlayer();

  // Speech and Logic
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String _lastWords = "";

  late List<QuantumParticle> _particles;
  late AnimationController _quantumController, _coreController, _pulseController;

  final String _apiUrl = 'https://tertulianoshow-terlinet-vision.hf.space/predict';

  @override
  void initState() {
    super.initState();
    _particles = List.generate(240, (index) => QuantumParticle());
    _quantumController = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
    _coreController = AnimationController(vsync: this, duration: const Duration(seconds: 20))..repeat();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _initSpeech();
    
    // Mostra orientações após o primeiro frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _showInstructions());
  }

  void _showInstructions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0A0A15),
        shape: RoundedRectangleBorder(side: const BorderSide(color: Colors.cyan, width: 1), borderRadius: BorderRadius.circular(15)),
        title: const Text("Bem-vindo ao TerlineT Vision", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _instructionItem(Icons.touch_app, "Toque no Núcleo", "Inicia ou para a visualização neural em tempo real."),
            _instructionItem(Icons.mic, "Pressione e Segure", "Ativa o comando de voz para perguntar algo ao Bee."),
            _instructionItem(Icons.flip_camera_ios, "Ícone de Câmera", "Alterna entre a câmera frontal e traseira."),
            const SizedBox(height: 10),
            const Text("O Bee narrará o ambiente e responderá suas dúvidas com inteligência artificial.", style: TextStyle(color: Colors.white70, fontSize: 12, fontStyle: FontStyle.italic)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("ENTENDIDO", style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _instructionItem(IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.amber, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                Text(desc, style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _initSpeech() async {
    await _speech.initialize();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cameraController?.dispose();
    _audioPlayer.dispose();
    _quantumController.dispose();
    _coreController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _listen() async {
    if (!_isListening) {
      bool available = await _speech.initialize();
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          onResult: (val) => setState(() {
            _lastWords = val.recognizedWords;
          }),
        );
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
      if (_lastWords.isNotEmpty) {
        _captureAndDetect(customQuery: _lastWords);
      }
    }
  }

  Future<void> _playBase64Audio(String base64String) async {
    try {
      if (kIsWeb) {
        await _audioPlayer.play(UrlSource('data:audio/mp3;base64,$base64String'));
      } else {
        final bytes = base64Decode(base64String);
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/narration.mp3');
        await file.writeAsBytes(bytes);
        await _audioPlayer.play(DeviceFileSource(file.path));
      }
    } catch (e) {
      print('Erro áudio: $e');
    }
  }

  Future<void> _toggleRealTime() async {
    if (_isRealTime) {
      _timer?.cancel();
      await _cameraController?.dispose();
      setState(() {
        _isRealTime = false;
        _cameraController = null;
        _description = "";
      });
    } else {
      if (_cameras.isEmpty) {
        _showNoCameraAlert();
        return;
      }
      _cameraController = CameraController(_cameras[_selectedCameraIndex], ResolutionPreset.medium, enableAudio: false);
      try {
        await _cameraController!.initialize();
        setState(() { _isRealTime = true; _imageBytes = null; });
      } catch (e) {
        print('Erro câmera: $e');
      }
    }
  }

  void _showNoCameraAlert() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.videocam_off, color: Colors.white),
            SizedBox(width: 10),
            Text("Nenhuma câmera detectada neste dispositivo."),
          ],
        ),
        backgroundColor: Colors.redAccent.withOpacity(0.8),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(label: "OK", textColor: Colors.white, onPressed: () {}),
      ),
    );
  }

  void _switchCamera() async {
    if (_cameras.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Apenas uma câmera detectada."), duration: Duration(seconds: 2))
      );
      return;
    }
    
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    
    if (_isRealTime) {
      // Se estiver em tempo real, reinicia a câmera com o novo índice
      await _cameraController?.dispose();
      _cameraController = CameraController(
        _cameras[_selectedCameraIndex], 
        ResolutionPreset.medium, 
        enableAudio: false
      );
      try {
        await _cameraController!.initialize();
        setState(() {});
      } catch (e) {
        print('Erro ao trocar câmera: $e');
      }
    } else {
      setState(() {});
    }
  }

  Future<void> _captureAndDetect({String? customQuery}) async {
    if (_cameraController == null || !_cameraController!.value.isInitialized || _isLoading) return;
    try {
      final XFile file = await _cameraController!.takePicture();
      final bytes = await file.readAsBytes();
      _detectObjects(file, bytes, query: customQuery);
    } catch (e) {
      print('Erro captura: $e');
    }
  }

  Future<void> _detectObjects(XFile file, Uint8List bytes, {String? query}) async {
    setState(() { _isLoading = true; });
    try {
      var request = http.MultipartRequest('POST', Uri.parse(_apiUrl));
      request.files.add(http.MultipartFile.fromBytes('image', bytes, filename: file.name));
      if (query != null) request.fields['user_query'] = query;
      request.fields['camera_type'] = _selectedCameraIndex == 0 ? "traseira" : "frontal";

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _description = data['description'] ?? "";
          _imageBytes = bytes;
        });
        if (data['audio'] != null) _playBase64Audio(data['audio']);
      }
    } catch (e) {
      print('Erro conexão: $e');
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020205),
      body: Stack(
        children: [
          Positioned.fill(child: AnimatedBuilder(animation: _quantumController, builder: (context, child) => CustomPaint(painter: QuantumSwarmPainter(_particles, _quantumController.value, _isRealTime)))),
          
          if (_isRealTime && _cameraController != null && _cameraController!.value.isInitialized)
            Positioned.fill(child: FittedBox(fit: BoxFit.cover, child: SizedBox(width: _cameraController!.value.previewSize!.height, height: _cameraController!.value.previewSize!.width, child: CameraPreview(_cameraController!))))
          else if (_imageBytes != null)
            Positioned.fill(child: Image.memory(_imageBytes!, fit: BoxFit.cover)),

          Positioned.fill(child: Container(color: Colors.black.withOpacity(0.4))),
          const Positioned.fill(child: TechGridBackground()),

          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(width: 50), // Espaçador para centralizar o header
                    const HolographicHeader(),
                    Padding(
                      padding: const EdgeInsets.only(right: 20),
                      child: IconButton(
                        icon: Icon(
                          _selectedCameraIndex == 0 ? Icons.camera_rear : Icons.camera_front,
                          color: Colors.cyan.withOpacity(0.7),
                        ),
                        onPressed: _switchCamera,
                        tooltip: "Trocar Câmera",
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Center(
                  child: NeuralBeeCore(
                    isActive: _isRealTime,
                    isLoading: _isLoading,
                    isListening: _isListening,
                    onTap: _toggleRealTime,
                    onLongPress: _listen,
                    rotation: _coreController,
                    pulse: _pulseController,
                  ),
                ),
                const Spacer(),
                if (_description.isNotEmpty) NarrativePanel(description: _description),
                const FooterSection(),
                const SizedBox(height: 10),
              ],
            ),
          ),
          if (_isRealTime || _imageBytes != null) const Positioned.fill(child: ScanningLine()),
        ],
      ),
    );
  }
}

// --- CORE UI ---

class NeuralBeeCore extends StatelessWidget {
  final bool isActive, isLoading, isListening;
  final VoidCallback onTap, onLongPress;
  final Animation<double> rotation, pulse;
  const NeuralBeeCore({super.key, required this.isActive, required this.isLoading, required this.isListening, required this.onTap, required this.onLongPress, required this.rotation, required this.pulse});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      onLongPressUp: onLongPress,
      child: AnimatedBuilder(
        animation: Listenable.merge([rotation, pulse]),
        builder: (context, child) => Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(width: 300, height: 300, child: CustomPaint(painter: NeuralCorePainter(rotation: rotation.value, pulse: pulse.value, isActive: isActive, isListening: isListening))),
            if (isListening) const Icon(Icons.mic, color: Colors.cyan, size: 40),
            if (isLoading) const CircularProgressIndicator(color: Colors.amber),
          ],
        ),
      ),
    );
  }
}

class NeuralCorePainter extends CustomPainter {
  final double rotation, pulse;
  final bool isActive, isListening;
  NeuralCorePainter({required this.rotation, required this.pulse, required this.isActive, required this.isListening});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseColor = isListening ? Colors.cyanAccent : (isActive ? Colors.amber : Colors.cyan);
    for (int i = 0; i < 4; i++) {
      final ringRotation = rotation * (i + 1) * (i.isEven ? 1 : -1);
      final ringPaint = Paint()..color = baseColor.withOpacity(0.1)..style = PaintingStyle.stroke..strokeWidth = 0.5;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(ringRotation);
      final rect = Rect.fromCircle(center: Offset.zero, radius: 70.0 + (i * 25));
      canvas.drawArc(rect, 0, math.pi * 0.5, false, ringPaint);
      canvas.drawArc(rect, math.pi, math.pi * 0.5, false, ringPaint);
      canvas.restore();
    }
    final coreRadius = 50.0 + (pulse * (isListening ? 15.0 : 8.0));
    final coreGradient = RadialGradient(colors: [baseColor, baseColor.withOpacity(0.2), Colors.transparent], stops: const [0.1, 0.6, 1.0]).createShader(Rect.fromCircle(center: center, radius: coreRadius));
    canvas.drawCircle(center, coreRadius * 1.8, Paint()..color = baseColor.withOpacity(0.05)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30));
    canvas.drawCircle(center, coreRadius, Paint()..shader = coreGradient);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// (QuantumParticle, SwarmPainter, TechGridBackground, etc. mantidos conforme versão anterior para brevidade)

class QuantumParticle {
  late double x, y, vx, vy, size;
  late Color color;
  static final math.Random _rand = math.Random();
  QuantumParticle() { respawn(); }
  void respawn() { 
    x = _rand.nextDouble() * 500; 
    y = _rand.nextDouble() * 800; 
    vx = (_rand.nextDouble() - 0.5) * 4; 
    vy = (_rand.nextDouble() - 0.5) * 4; 
    size = _rand.nextDouble() * 1.8 + 0.5; // Partículas levemente maiores
    color = _rand.nextBool() ? Colors.cyanAccent : Colors.amberAccent; // Cores mais vivas
  }
  void update(Size screen, bool isHighEnergy, List<QuantumParticle> others) {
    double centerX = 0, centerY = 0, avgVx = 0, avgVy = 0, closeDx = 0, closeDy = 0;
    int count = 0;
    for (var other in others) {
      if (other == this) continue;
      double dx = x - other.x, dy = y - other.y, d = math.sqrt(dx * dx + dy * dy);
      if (d < 60.0) { centerX += other.x; centerY += other.y; avgVx += other.vx; avgVy += other.vy; count++; if (d < 20.0) { closeDx += dx; closeDy += dy; } }
    }
    if (count > 0) { centerX /= count; centerY /= count; avgVx /= count; avgVy /= count; vx += (centerX - x) * 0.005; vy += (centerY - y) * 0.005; vx += (avgVx - vx) * 0.05; vy += (avgVy - vy) * 0.05; }
    vx += closeDx * 0.05; vy += closeDy * 0.05;
    vx += (screen.width / 2 - x) * 0.0005; vy += (screen.height / 2 - y) * 0.0005;
    vx += (_rand.nextDouble() - 0.5) * 0.1; vy += (_rand.nextDouble() - 0.5) * 0.1;
    double limit = isHighEnergy ? 3.5 : 1.8;
    double speed = math.sqrt(vx * vx + vy * vy);
    if (speed > limit) { vx = (vx / speed) * limit; vy = (vy / speed) * limit; }
    x += vx; y += vy;
    if (x < -20) x = screen.width + 20; if (x > screen.width + 20) x = -20;
    if (y < -20) y = screen.height + 20; if (y > screen.height + 20) y = -20;
  }
}

class QuantumSwarmPainter extends CustomPainter {
  final List<QuantumParticle> particles;
  final double animation;
  final bool isHighEnergy;
  QuantumSwarmPainter(this.particles, this.animation, this.isHighEnergy);
  
  @override
  void paint(Canvas canvas, Size size) {
    for (var p in particles) {
      p.update(size, isHighEnergy, particles);
      
      // Cálculo de opacidade pulsante intensificada
      final opacity = (0.3 + (math.sin(animation * 2 * math.pi + p.x * 0.01) + 1) * 0.35).clamp(0.0, 1.0);
      
      // Efeito de brilho externo (Glow/Bloom)
      final glowPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = p.color.withOpacity(opacity * 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(Offset(p.x, p.y), p.size * 2.5, glowPaint);

      // Núcleo sólido e brilhante da partícula
      final corePaint = Paint()
        ..style = PaintingStyle.fill
        ..color = p.color.withOpacity(opacity);
      canvas.drawCircle(Offset(p.x, p.y), p.size, corePaint);
    }
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class TechGridBackground extends StatelessWidget {
  const TechGridBackground({super.key});
  @override Widget build(BuildContext context) { return CustomPaint(painter: GridPainter()); }
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.cyan.withOpacity(0.03)..strokeWidth = 0.5;
    for (double i = 0; i < size.width; i += 50.0) canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    for (double i = 0; i < size.height; i += 50.0) canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class HolographicHeader extends StatelessWidget {
  const HolographicHeader({super.key});
  @override Widget build(BuildContext context) {
    return Column(
      children: [
        Text('TERLINET', style: TextStyle(color: Colors.cyan[400], fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 12)),
        const Text('NEURAL SWARM VISION', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w200, letterSpacing: 3)),
        const SizedBox(height: 10),
        Container(width: 80, height: 1, decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, Colors.cyan[400]!, Colors.transparent]))),
      ],
    );
  }
}

class ScanningLine extends StatefulWidget {
  const ScanningLine({super.key});
  @override State<ScanningLine> createState() => _ScanningLineState();
}

class _ScanningLineState extends State<ScanningLine> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override void initState() { super.initState(); _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat(); }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) => Positioned(
        top: _ctrl.value * MediaQuery.of(context).size.height,
        left: 0,
        right: 0,
        child: Container(height: 1, color: Colors.cyan.withOpacity(0.4), decoration: BoxDecoration(boxShadow: [BoxShadow(color: Colors.cyan.withOpacity(0.3), blurRadius: 10, spreadRadius: 2)])),
      ),
    );
  }
}

class NarrativePanel extends StatelessWidget {
  final String description;
  const NarrativePanel({super.key, required this.description});
  @override Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(25),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(2), border: Border(left: BorderSide(color: Colors.amber[600]!, width: 2))),
      child: Text(description, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5, fontStyle: FontStyle.italic)),
    );
  }
}

class FooterSection extends StatelessWidget {
  const FooterSection({super.key});
  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) print('Erro URL: $url');
  }
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 30),
      child: Column(
        children: [
          const Text('© 2026 TerlineT - Criatividade sem limites', style: TextStyle(color: Colors.cyan, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            InkWell(onTap: () => _launchUrl('mailto:terlinetdeveloper@gmail.com'), child: Row(children: [Icon(Icons.email, size: 12, color: Colors.cyan.withOpacity(0.7)), const SizedBox(width: 5), const Text('terlinetdeveloper@gmail.com', style: TextStyle(color: Colors.white54, fontSize: 10))])),
            const SizedBox(width: 20),
            InkWell(onTap: () => _launchUrl('tel:+5511981574046'), child: Row(children: [Icon(Icons.phone, size: 12, color: Colors.cyan.withOpacity(0.7)), const SizedBox(width: 5), const Text('11 98157-4046', style: TextStyle(color: Colors.white54, fontSize: 10))])),
          ]),
          const SizedBox(height: 15),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(icon: Icon(Icons.facebook, color: Colors.cyan.withOpacity(0.6), size: 18), onPressed: () => _launchUrl('https://www.facebook.com/tertuliano.oliveira'), constraints: const BoxConstraints(), padding: EdgeInsets.zero),
            const SizedBox(width: 25),
            GestureDetector(onTap: () => _launchUrl('https://x.com/Tertulianonews'), child: const Text('𝕏', style: TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.bold))),
          ]),
        ],
      ),
    );
  }
}
