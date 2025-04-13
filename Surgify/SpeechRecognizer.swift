//
//  SpeechRecognizer.swift
//  Surgify
//
//  Created by Pranav Kumar on 4/13/25.
//

import SwiftUI
import RealityKit
import ARKit       // For AR functionality
import Speech      // For speech recognition
import AVFoundation
import Combine     // For handling async operations and state changes
import Vision      // For hand-pose detection (pinch gesture)

// MARK: - SpeechRecognizer Class

class SpeechRecognizer: ObservableObject {
    @Published var transcript: String = ""
    @Published var command: String = ""
    @Published var identifiedTool: String? = nil   // Stores the identified tool name
    
    // Updated tool keywords: only Vacuum, Scalpel, and Tweezer
    private let toolKeywords = ["vacuum", "scalpel", "tweezer"]
    private var audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    
    // This flag controls continuous speech recognition.
    private var shouldKeepRecording: Bool = false
    
    // Extracts text found between "nurse" and "please", ignoring case.
    // Uses the last match so that a new command supersedes an old one.
    private func extractCommand(from text: String) -> String? {
        let pattern = "(?:doctor|dr\\.?)[\\s:]+(.*?)[\\s,]*please"
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let nsString = text as NSString
            let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
            if let match = results.last, match.numberOfRanges > 1 {
                let extracted = nsString.substring(with: match.range(at: 1))
                return extracted.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            print("Regex error: \(error)")
        }
        return nil
    }
    
    // Identifies the first matching tool keyword in the command.
    private func identifyTool(from command: String) {
        let lowercasedCommand = command.lowercased()
        
        // Add synonym mapping
        let synonymMap: [String: String] = [
            "blade": "scalpel"
        ]
        
        // Check if any synonyms are in the command
        for (synonym, actualTool) in synonymMap {
            if lowercasedCommand.contains(synonym) {
                if self.identifiedTool != actualTool {
                    DispatchQueue.main.async {
                        self.identifiedTool = actualTool
                    }
                    print("Identified tool via synonym '\(synonym)': \(actualTool)")
                }
                return
            }
        }
        
        // Check against direct tool keywords
        for keyword in toolKeywords {
            if lowercasedCommand.contains(keyword) {
                if self.identifiedTool != keyword {
                    DispatchQueue.main.async {
                        self.identifiedTool = keyword
                    }
                    print("Identified tool: \(keyword)")
                }
                return
            }
        }
        
        // If no tool is identified, clear the previously selected tool.
        if self.identifiedTool != nil {
            DispatchQueue.main.async {
                self.identifiedTool = nil
            }
            print("No tool identified from command: \(command)")
        }
    }
    
    func startRecording() {
        // Mark that recording should keep going.
        shouldKeepRecording = true
        print("Starting continuous speech recognition...")
        
        // Cancel any existing task.
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Set up the audio session.
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio session configuration failed: \(error)")
        }
        
        // Prepare the recognition request.
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else {
            fatalError("Unable to create SFSpeechAudioBufferRecognitionRequest object.")
        }
        request.shouldReportPartialResults = true
        
        // Install an audio tap on the input node.
        let inputNode = audioEngine.inputNode
        guard inputNode.outputFormat(forBus: 0).channelCount > 0 else {
            print("❌ Input node has zero channels or invalid format.")
            return
        }
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer, _) in
            request.append(buffer)
        }
        
        // Start the audio engine.
        audioEngine.prepare()
        do {
            try audioEngine.start()
            print("Audio engine started.")
        } catch {
            print("Audio engine failed to start: \(error)")
        }
        
        // Begin recognition.
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let currentTranscript = result.bestTranscription.formattedString
                // Log and update the transcript.
                DispatchQueue.main.async {
                    self.transcript = currentTranscript
                }
                print("Transcript: \(currentTranscript)")
                
                if let cmd = self.extractCommand(from: currentTranscript) {
                    // Log and update the command, then clear the transcript.
                    DispatchQueue.main.async {
                        self.command = cmd
                        self.transcript = ""
                    }
                    print("Extracted command: \(cmd)")
                    self.identifyTool(from: cmd)
                } else {
                    DispatchQueue.main.async {
                        self.command = ""
                    }
                    print("No valid command extracted.")
                    self.identifyTool(from: "")
                }
            }
            
            // If there is an error or the result is final, restart the recording if needed.
            if error != nil || (result?.isFinal ?? false) {
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                self.recognitionRequest = nil
                self.recognitionTask = nil
                if self.shouldKeepRecording {
                    print("Restarting speech recognition...")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.startRecording()
                    }
                }
            }
        }
    }
    
    func stopRecording() {
        // Mark that recording should stop.
        shouldKeepRecording = false
        audioEngine.stop()
        recognitionRequest?.endAudio()
        print("Speech recognition stopped.")
    }
    
    // Request microphone and speech recognition permissions.
    func requestPermission() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            OperationQueue.main.addOperation {
                switch authStatus {
                case .authorized:
                    print("Speech recognition authorized.")
                case .denied, .restricted, .notDetermined:
                    print("Speech recognition not authorized.")
                @unknown default:
                    fatalError("Unknown authorization status.")
                }
            }
        }
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted {
                    print("Microphone permission granted.")
                } else {
                    print("Microphone permission denied.")
                }
            }
        }
    }
    
    init() {
        requestPermission()
    }
}
