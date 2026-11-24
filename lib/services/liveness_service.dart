import 'dart:math';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

enum LivenessChallenge {
  smile, // Senyum lebar
  blink, // Kedipkan mata
  turnLeft, // Tengok ke kiri
  turnRight, // Tengok ke kanan
}

class LivenessChallengeResult {
  final bool isSuccess;
  final String message;
  final double confidence;

  LivenessChallengeResult({
    required this.isSuccess,
    required this.message,
    this.confidence = 0.0,
  });
}

class LivenessService {
  late final FaceDetector _faceDetector;

  LivenessService() {
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true, // Untuk senyum & mata terbuka/tertutup
        enableTracking: true,
        enableLandmarks: true,
        performanceMode: FaceDetectorMode.fast,
        minFaceSize: 0.25,
      ),
    );
  }

  // Generate random challenge for employee
  static LivenessChallenge generateRandomChallenge() {
    final challenges = [
      LivenessChallenge.smile,
      LivenessChallenge.blink,
      LivenessChallenge.turnLeft,
      LivenessChallenge.turnRight,
    ];
    return challenges[Random().nextInt(challenges.length)];
  }

  static String getChallengeInstruction(LivenessChallenge challenge) {
    switch (challenge) {
      case LivenessChallenge.smile:
        return 'Tersenyumlah ke arah kamera';
      case LivenessChallenge.blink:
        return 'Berkedip satu atau dua kali';
      case LivenessChallenge.turnLeft:
        return 'Tengokkan kepala sedikit ke kiri';
      case LivenessChallenge.turnRight:
        return 'Tengokkan kepala sedikit ke kanan';
    }
  }

  // Generate a random 3-digit challenge token
  static String generateRandomToken() {
    final rand = Random().nextInt(900) + 100;
    return rand.toString();
  }

  Future<List<Face>> processImage(InputImage inputImage) async {
    try {
      return await _faceDetector.processImage(inputImage);
    } catch (e) {
      return [];
    }
  }

  LivenessChallengeResult verifyFaceChallenge(Face face, LivenessChallenge challenge) {
    switch (challenge) {
      case LivenessChallenge.smile:
        final smileProb = face.smilingProbability ?? 0.0;
        if (smileProb > 0.65) {
          return LivenessChallengeResult(
            isSuccess: true,
            message: 'Senyuman terdeteksi! (Asli)',
            confidence: smileProb,
          );
        }
        return LivenessChallengeResult(
          isSuccess: false,
          message: 'Silakan tersenyum lebih lebar',
        );

      case LivenessChallenge.blink:
        final leftEye = face.leftEyeOpenProbability ?? 1.0;
        final rightEye = face.rightEyeOpenProbability ?? 1.0;
        if (leftEye < 0.25 || rightEye < 0.25) {
          return LivenessChallengeResult(
            isSuccess: true,
            message: 'Kedipan terdeteksi! (Asli)',
            confidence: 1.0,
          );
        }
        return LivenessChallengeResult(
          isSuccess: false,
          message: 'Silakan berkedip ke arah kamera',
        );

      case LivenessChallenge.turnLeft:
        final headY = face.headEulerAngleY ?? 0.0;
        if (headY > 18.0) {
          return LivenessChallengeResult(
            isSuccess: true,
            message: 'Tengok kiri terdeteksi! (Asli)',
            confidence: headY / 30.0,
          );
        }
        return LivenessChallengeResult(
          isSuccess: false,
          message: 'Tengokkan kepala ke kiri sedikit lagi',
        );

      case LivenessChallenge.turnRight:
        final headY = face.headEulerAngleY ?? 0.0;
        if (headY < -18.0) {
          return LivenessChallengeResult(
            isSuccess: true,
            message: 'Tengok kanan terdeteksi! (Asli)',
            confidence: (-headY) / 30.0,
          );
        }
        return LivenessChallengeResult(
          isSuccess: false,
          message: 'Tengokkan kepala ke kanan sedikit lagi',
        );
    }
  }

  void dispose() {
    _faceDetector.close();
  }
}
