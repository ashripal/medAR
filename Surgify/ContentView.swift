//
//  ContentView.swift
//  Surgify
//
//  Updated with continuous pinch-to-move logic so that the selected tool always comes to the hand's coordinates when pinched and follows the hand as long as the pinch gesture persists.
//  Also includes continuous speech command recognition, AR functionality, collision detection between the vacuum and tumour with a countdown, replacement of the tumour model after countdown, tweezers scaled down by an extra 10x, and now a single green sphere that surrounds the tumour.
//  Updated so that once the countdown reaches 0 (for vacuum), it doesn't start again until the user goes back and clicks on the see brain again.
//  Created by Yash Aggarwal on 11/04/25.
import SwiftUI
import RealityKit
import ARKit       // For AR functionality
import Speech      // For speech recognition
import AVFoundation
import Combine     // For handling async operations and state changes
import Vision      // For hand-pose detection (pinch gesture)

// Custom colors for a consistent theme
extension Color {
    static let surgifyPrimary = Color(red: 0.1, green: 0.6, blue: 0.9)
    static let surgifyAccent = Color(red: 0.0, green: 0.8, blue: 0.6)
    static let surgifyDark = Color(red: 0.1, green: 0.2, blue: 0.3)
    static let surgifyLight = Color(red: 0.95, green: 0.98, blue: 1.0)
}

// Custom button style for a consistent look
struct SurgifyButtonStyle: ButtonStyle {
    var isSelected: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                isSelected ? Color.surgifyAccent : Color.surgifyPrimary,
                                isSelected ? Color.surgifyPrimary : Color.surgifyDark
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 5, x: 0, y: 3)
            )
            .foregroundColor(.white)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// Custom button style for scale animation on press
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct ContentView: View {
    @State private var showARView = false
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @State private var selectedTool: String? = nil
    // New state: For displaying the countdown overlay.
    @State private var collisionCountdown: Int? = nil
    // New state: For displaying the scalpel precision score
    @State private var scalpelPrecisionScore: Int? = nil
    // New state: To show a success message when tumour is detached
    @State private var showTumourExtractedMessage: Bool = false
    
    // Animation states for landing page
    @State private var slideInLogo = false
    @State private var slideInButtons = false

    // List of available tools and corresponding SF Symbols.
    private let tools = ["vacuum", "scalpel", "tweezer"]
    private let toolIcons: [String: String] = [
        "vacuum": "waveform.circle.fill",
        "scalpel": "scissors",
        "tweezer": "hand.draw.fill"
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                if showARView {
                    ARViewContainer(selectedTool: $selectedTool, collisionCountdown: $collisionCountdown, scalpelPrecisionScore: $scalpelPrecisionScore, showTumourExtractedMessage: $showTumourExtractedMessage)
                        .edgesIgnoringSafeArea(.all)
                        .overlay(alignment: .topLeading) {
                            Button(action: {
                                showARView = false
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 16, weight: .bold))
                                    Text("Back")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(Color.black.opacity(0.6))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 20)
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                )
                                .foregroundColor(.white)
                            }
                            .shadow(color: Color.black.opacity(0.3), radius: 5, x: 0, y: 2)
                            .padding(.top, 16)
                            .padding(.leading, 16)
                        }
                        // Toolbar UI overlay - improved with glass effect and better layout
                        .overlay(alignment: .bottom) {
                            VStack {
                                HStack(spacing: 15) {
                                    ForEach(tools, id: \.self) { tool in
                                        Button(action: {
                                            // Haptic feedback when selecting a tool
                                            let generator = UIImpactFeedbackGenerator(style: .medium)
                                            generator.impactOccurred()
                                            
                                            // Set the selected tool when tapped
                                            selectedTool = tool
                                        }) {
                                            VStack(spacing: 8) {
                                                Image(systemName: toolIcons[tool] ?? "questionmark.circle")
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(width: 32, height: 32)
                                                    .foregroundColor(selectedTool == tool ? Color.surgifyAccent : .white)
                                                    .shadow(color: selectedTool == tool ? Color.surgifyAccent.opacity(0.7) : .clear, radius: 5)
                                                
                                                Text(tool.capitalized)
                                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                                    .foregroundColor(.white)
                                            }
                                            .frame(width: 80, height: 100)
                                            .background(
                                                RoundedRectangle(cornerRadius: 18)
                                                    .fill(Color.black.opacity(selectedTool == tool ? 0.75 : 0.5))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 18)
                                                            .stroke(
                                                                LinearGradient(
                                                                    gradient: Gradient(colors: [
                                                                        selectedTool == tool ? Color.surgifyAccent : Color.white.opacity(0.3),
                                                                        selectedTool == tool ? Color.surgifyPrimary : Color.white.opacity(0.1)
                                                                    ]),
                                                                    startPoint: .topLeading,
                                                                    endPoint: .bottomTrailing
                                                                ),
                                                                lineWidth: selectedTool == tool ? 2 : 1
                                                            )
                                                    )
                                            )
                                            .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .scaleEffect(selectedTool == tool ? 1.05 : 1.0)
                                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedTool)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 15)
                                .padding(.bottom, 25)
                                .background(
                                    RoundedRectangle(cornerRadius: 30)
                                        .fill(Color.black.opacity(0.3))
                                        .background(
                                            RoundedRectangle(cornerRadius: 30)
                                                .fill(Material.ultraThinMaterial)
                                        )
                                        .shadow(color: Color.black.opacity(0.3), radius: 15, x: 0, y: 5)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 30)
                                        .stroke(
                                            LinearGradient(
                                                gradient: Gradient(colors: [Color.white.opacity(0.5), Color.white.opacity(0.1)]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 25)
                        }
                        // Countdown overlay with improved animation
                        .overlay {
                            if let countdown = collisionCountdown {
                                ZStack {
                                    // Outer pulsing circle
                                    Circle()
                                        .fill(Color.surgifyAccent.opacity(0.2))
                                        .frame(width: 120, height: 120)
                                        .scaleEffect(countdown % 2 == 0 ? 1.1 : 1.0)
                                        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: countdown)
                                    
                                    // Inner solid circle
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(colors: [Color.surgifyDark, Color.surgifyPrimary]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 90, height: 90)
                                        .shadow(color: Color.black.opacity(0.3), radius: 10)
                                    
                                    // Text
                                    Text("\(countdown)")
                                        .font(.system(size: 40, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                }
                                .transition(.scale.combined(with: .opacity))
                                .animation(.spring(response: 0.3), value: countdown)
                            }
                        }
                        // Scalpel precision score overlay - redesigned for better visibility
                        .overlay(alignment: .topTrailing) {
                            if let score = scalpelPrecisionScore {
                                VStack(alignment: .center, spacing: 6) {
                                    Text("Precision")
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundColor(.white.opacity(0.9))
                                    
                                    HStack(alignment: .lastTextBaseline, spacing: 0) {
                                        Text("\(score)")
                                            .font(.system(size: 44, weight: .bold, design: .rounded))
                                        Text("%")
                                            .font(.system(size: 24, weight: .bold, design: .rounded))
                                            .padding(.leading, 2)
                                    }
                                    .foregroundColor(scoreColor(for: score))
                                    .shadow(color: scoreColor(for: score).opacity(0.7), radius: 3)
                                    
                                    // Progress bar
                                    ZStack(alignment: .leading) {
                                        // Background
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.white.opacity(0.2))
                                            .frame(width: 100, height: 8)
                                        
                                        // Foreground
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(scoreColor(for: score))
                                            .frame(width: max(4, CGFloat(score) * 100 / 100), height: 8)
                                            .animation(.spring(response: 0.3), value: score)
                                    }
                                }
                                .padding(.vertical, 15)
                                .padding(.horizontal, 20)
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(Color.black.opacity(0.6))
                                        .background(
                                            RoundedRectangle(cornerRadius: 20)
                                                .fill(Material.ultraThinMaterial)
                                        )
                                        .shadow(color: Color.black.opacity(0.3), radius: 10)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(
                                            LinearGradient(
                                                gradient: Gradient(colors: [Color.white.opacity(0.5), Color.white.opacity(0.1)]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                                .padding(.top, 16)
                                .padding(.trailing, 16)
                                .transition(.move(edge: .top).combined(with: .opacity))
                                .animation(.spring(response: 0.5), value: score)
                            }
                        }
                        // Success message overlay with improved animation and design
                        .overlay {
                            if showTumourExtractedMessage {
                                VStack(spacing: 20) {
                                    // Success icon
                                    ZStack {
                                        Circle()
                                            .fill(Color.surgifyAccent.opacity(0.2))
                                            .frame(width: 100, height: 100)
                                        
                                        Circle()
                                            .fill(Color.surgifyAccent)
                                            .frame(width: 80, height: 80)
                                        
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 40, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                    
                                    Text("Tumour Successfully Extracted!")
                                        .font(.system(size: 24, weight: .bold, design: .rounded))
                                        .multilineTextAlignment(.center)
                                        .foregroundColor(.white)
                                    
                                    Text("Excellent surgical technique")
                                        .font(.system(size: 16, weight: .medium, design: .rounded))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                .padding(.horizontal, 30)
                                .padding(.vertical, 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 30)
                                        .fill(Color.black.opacity(0.7))
                                        .background(
                                            RoundedRectangle(cornerRadius: 30)
                                                .fill(Material.ultraThinMaterial)
                                        )
                                        .shadow(color: Color.black.opacity(0.5), radius: 20)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 30)
                                        .stroke(
                                            LinearGradient(
                                                gradient: Gradient(colors: [Color.white.opacity(0.5), Color.white.opacity(0.1)]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                                .transition(.scale.combined(with: .opacity))
                                .animation(.spring(response: 0.6, dampingFraction: 0.7), value: showTumourExtractedMessage)
                                .onAppear {
                                    // Automatically dismiss after 3 seconds
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                        withAnimation(.easeOut(duration: 1.0)) {
                                            showTumourExtractedMessage = false
                                        }
                                    }
                                }
                            }
                        }
                }
                else {
                    ZStack {
                        // Modern gradient background
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.2, green: 0.0, blue: 0.4),  // Deep purple
                                Color(red: 0.1, green: 0.0, blue: 0.2)   // Dark purple/black
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .ignoresSafeArea()
                        
                        // Decorative animated blobs
                        ZStack {
                            // Top-right blob
                            Circle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.surgifyAccent, Color.surgifyPrimary.opacity(0.7)]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 300, height: 300)
                                .blur(radius: 60)
                                .offset(x: 150, y: -250)
                                .opacity(0.7)
                                .modifier(FloatingAnimation(duration: 5, yOffset: 20))
                            
                            // Bottom-left blob
                            Circle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.surgifyPrimary, Color.surgifyAccent.opacity(0.7)]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 350, height: 350)
                                .blur(radius: 60)
                                .offset(x: -150, y: 400)
                                .opacity(0.5)
                                .modifier(FloatingAnimation(duration: 7, yOffset: -20))
                            
                            // Animated smaller accent blobs
                            Circle()
                                .fill(Color.surgifyAccent.opacity(0.4))
                                .frame(width: 100, height: 100)
                                .blur(radius: 30)
                                .offset(x: -120, y: -200)
                                .modifier(FloatingAnimation(duration: 4, yOffset: 15))
                            
                            // Small decorative dots
                            ForEach(0..<20, id: \.self) { i in
                                Circle()
                                    .fill(Color.white.opacity(0.4))
                                    .frame(width: 4, height: 4)
                                    .offset(
                                        x: CGFloat.random(in: -180...180),
                                        y: CGFloat.random(in: -350...350)
                                    )
                                    .modifier(PulsatingOpacity(
                                        minOpacity: 0.2,
                                        maxOpacity: 0.7,
                                        duration: Double.random(in: 2...5)
                                    ))
                            }
                        }
                        
                        // Content container with glass effect
                        VStack(spacing: 40) {
                            // Logo and branding
                            VStack(spacing: 5) {
                                // Stethoscope icon and MedAR title with subtle animation
                                HStack(spacing: 15) {
                                    // App icon with subtle rotation effect
                                    Image(systemName: "stethoscope")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 60, height: 60)
                                        .foregroundColor(.white)
                                        .modifier(PulsatingScale(minScale: 1.0, maxScale: 1.05, duration: 3))
                                    
                                    // App name
                                    Text("MedAR")
                                        .font(.system(size: 60, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                }
                                .offset(y: slideInLogo ? 0 : -100)
                                .opacity(slideInLogo ? 1 : 0)
                                
                                // Tagline with typing animation effect
                                Text("Augmented Reality Surgical Training")
                                    .font(.system(size: 16, weight: .medium, design: .rounded))
                                    .foregroundColor(.white.opacity(0.8))
                                    .padding(.top, 4)
                                    .modifier(TypewriterText(text: "Augmented Reality Surgical Training", duration: 2.0))
                                    .opacity(slideInLogo ? 1 : 0)
                            }
                            .padding(.top, 80)
                            
                            Spacer()
                            
                            // Action buttons with glass effect
                            VStack(spacing: 24) {
                                // Surgery button
                                Button(action: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                        showARView = true
                                    }
                                }) {
                                    HStack(spacing: 15) {
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 24))
                                        
                                        Text("Begin Surgery")
                                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                                            .tracking(0.5)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 60)
                                    .background(
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 20)
                                                .fill(Color.black.opacity(0.3))
                                            
                                            // Glass effect
                                            RoundedRectangle(cornerRadius: 20)
                                                .fill(
                                                    LinearGradient(
                                                        gradient: Gradient(colors: [
                                                            Color.surgifyPrimary.opacity(0.7),
                                                            Color.surgifyPrimary.opacity(0.4)
                                                        ]),
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .opacity(0.8)
                                                .modifier(ShimmerEffect())
                                        }
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .stroke(
                                                LinearGradient(
                                                    gradient: Gradient(colors: [Color.white.opacity(0.6), Color.white.opacity(0.2)]),
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1.5
                                            )
                                    )
                                    .shadow(color: Color.surgifyPrimary.opacity(0.5), radius: 15, x: 0, y: 8)
                                    .foregroundColor(.white)
                                }
                                .buttonStyle(ScaleButtonStyle())
                                .transition(.scale.combined(with: .opacity))
                                .offset(x: slideInButtons ? 0 : -500)
                                .opacity(slideInButtons ? 1 : 0)
                                
                                // Walkthrough button
                                NavigationLink {
                                    WalkthroughARView()
                                        .navigationTitle("AR Walkthrough")
                                        .navigationBarTitleDisplayMode(.inline)
                                } label: {
                                    HStack(spacing: 15) {
                                        Image(systemName: "doc.text")
                                            .font(.system(size: 22))
                                        
                                        Text("Enter Walkthrough")
                                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                                            .tracking(0.5)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 60)
                                    .background(
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 20)
                                                .fill(Color.black.opacity(0.3))
                                            
                                            // Glass effect
                                            RoundedRectangle(cornerRadius: 20)
                                                .fill(Material.ultraThinMaterial)
                                        }
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .stroke(
                                                LinearGradient(
                                                    gradient: Gradient(colors: [Color.white.opacity(0.6), Color.white.opacity(0.2)]),
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1.5
                                            )
                                    )
                                    .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
                                    .foregroundColor(.white)
                                }
                                .buttonStyle(ScaleButtonStyle())
                                .transition(.scale.combined(with: .opacity))
                                .offset(x: slideInButtons ? 0 : 500)
                                .opacity(slideInButtons ? 1 : 0)
                            }
                            .padding(.horizontal, 30)
                            .padding(.bottom, 60)
                        }
                        .opacity(1)
                        .onAppear {
                            // Staggered entrance animations
                            withAnimation(.spring(response: 0.7, dampingFraction: 0.6).delay(0.1)) {
                                slideInLogo = true
                            }
                            
                            withAnimation(.spring(response: 0.7, dampingFraction: 0.6).delay(0.5)) {
                                slideInButtons = true
                            }
                        }
                    }
                }
            }
            .onChange(of: showARView) { newValue in
                if newValue {
                    // Start speech recognition when entering AR view.
                    speechRecognizer.requestPermission()
                    speechRecognizer.startRecording()
                } else {
                    // Stop speech recognition when leaving AR view.
                    speechRecognizer.stopRecording()
                }
            }
            .onReceive(speechRecognizer.$identifiedTool) { identifiedTool in
                self.selectedTool = identifiedTool
            }
            .onAppear {
                speechRecognizer.requestPermission()
            }
        }
        .preferredColorScheme(.dark) // Force dark mode for better AR visuals
    }
    
    // Helper function to determine the color based on the score
    private func scoreColor(for score: Int) -> Color {
        switch score {
        case 0..<40:
            return Color(red: 0.9, green: 0.3, blue: 0.3) // Refined red
        case 40..<70:
            return Color(red: 0.95, green: 0.8, blue: 0.2) // Refined yellow
        default:
            return Color.surgifyAccent // Use our theme accent color for good scores
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    // Bindings for the selected tool and countdown display.
    @Binding var selectedTool: String?
    @Binding var collisionCountdown: Int?
    // New binding for the scalpel precision score
    @Binding var scalpelPrecisionScore: Int?
    // New binding for the showTumourExtractedMessage
    @Binding var showTumourExtractedMessage: Bool
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self, selectedTool: $selectedTool, collisionCountdown: $collisionCountdown, scalpelPrecisionScore: $scalpelPrecisionScore, showTumourExtractedMessage: $showTumourExtractedMessage)
    }
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        
        // Configure the AR session.
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            configuration.frameSemantics.insert(.personSegmentationWithDepth)
            print("ℹ️ Requesting personSegmentationWithDepth.")
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
            print("ℹ️ Requesting sceneDepth.")
        }
        
        arView.session.run(configuration)
        arView.session.delegate = context.coordinator
        context.coordinator.arView = arView
        
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)
        
        context.coordinator.startHandTracking()
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // No dynamic updates needed.
    }
    
    class Coordinator: NSObject, ARSessionDelegate {
        weak var arView: ARView?
        // The currently selected tool's entity.
        var toolEntity: Entity?
        // Reference to the tumour model entity (for collision detection).
        var tumourEntity: Entity?
        // The green sphere entity that will surround the tumour.
        var tumourSphereEntity: ModelEntity? = nil
        // Vision hand-pose request setup.
        var handPoseRequest = VNDetectHumanHandPoseRequest()
        // Flag indicating whether the tool is actively following your pinch.
        var toolGrabbed: Bool = false
        // A fixed distance from the camera when positioning the tool.
        let fixedDepth: Float = 0.5
        // Timer for hand tracking.
        var handTrackingTimer: Timer?
        // Flag to prevent multiple brain placements.
        var brainPlaced: Bool = false
        
        // New property to track if hollow tumour is being grabbed with tweezers
        var hollowTumourGrabbed: Bool = false
        // New property to track if scalpel precision challenge is completed
        var scalpelPrecisionCompleted: Bool = false
        // Threshold for grabbing the hollow tumour (in meters)
        let tumourGrabThreshold: Float = 0.15
        
        // Bindings for the selected tool and the countdown overlay.
        var selectedTool: Binding<String?>
        var currentToolName: String? = nil
        var collisionCountdown: Binding<Int?>
        // New binding for the scalpel precision score
        var scalpelPrecisionScore: Binding<Int?>
        // New binding for the showTumourExtractedMessage
        var showTumourExtractedMessage: Binding<Bool>
        
        // Countdown management.
        var collisionCountdownActive: Bool = false
        var countdownTimer: Timer?
        // Indicates whether the tumour has already been replaced.
        var tumourReplaced: Bool = false
        
        // Scalpel precision score management
        var scalpelPrecisionScoreActive: Bool = false
        var scalpelScoreTimer: Timer?
        var scalpelTrackingTimer: Timer?
        var currentScore: Int = 100
        var scalpelMultiplier: Int = 1
        var scalpelTimeRemaining: Int = 10
        
        init(_ parent: ARViewContainer, selectedTool: Binding<String?>, collisionCountdown: Binding<Int?>, scalpelPrecisionScore: Binding<Int?>, showTumourExtractedMessage: Binding<Bool>) {
            self.selectedTool = selectedTool
            self.collisionCountdown = collisionCountdown
            self.scalpelPrecisionScore = scalpelPrecisionScore
            self.showTumourExtractedMessage = showTumourExtractedMessage
            super.init()
            // Configure to track just one hand.
            handPoseRequest.maximumHandCount = 1
        }
        
        /// Start periodic hand tracking.
        func startHandTracking() {
            handTrackingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.processCurrentFrame()
            }
        }
        
        /// Process the current AR frame: detect pinch gesture and update the selected tool's position to the hand's coordinates unconditionally when pinched.
        func processCurrentFrame() {
            guard let arView = arView, let currentFrame = arView.session.currentFrame else { return }
            
            let pixelBuffer = currentFrame.capturedImage
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
            try? handler.perform([handPoseRequest])
            
            guard let observations = handPoseRequest.results, !observations.isEmpty else {
                toolGrabbed = false
                return
            }
            
            // Use the first observed hand.
            guard let observation = observations.first,
                  let thumbTip = try? observation.recognizedPoint(.thumbTip),
                  let indexTip = try? observation.recognizedPoint(.indexTip),
                  thumbTip.confidence > 0.3, indexTip.confidence > 0.3 else {
                toolGrabbed = false
                return
            }
            
            // Compute the average position of thumb and index finger.
            let thumbPoint = SIMD2<Float>(Float(thumbTip.location.x), Float(thumbTip.location.y))
            let indexPoint = SIMD2<Float>(Float(indexTip.location.x), Float(indexTip.location.y))
            let pinchDistance = simd_distance(thumbPoint, indexPoint)
            let pinchThreshold: Float = 0.1
            // If pinch distance is above threshold, the user is not pinching.
            if pinchDistance >= pinchThreshold {
                toolGrabbed = false
                
                // Only set hollowTumourGrabbed to false if it's currently grabbed
                // This explicitly handles the release of the tumour
                if hollowTumourGrabbed {
                    print("👋 Pinch released - tumour no longer grabbed")
                    hollowTumourGrabbed = false
                }
                return
            }
            
            // A pinch is detected – mark the tool as grabbed.
            toolGrabbed = true
            
            // Compute the average hand screen coordinate.
            let avgX = (thumbTip.location.x + indexTip.location.x) / 2
            let avgY = (thumbTip.location.y + indexTip.location.y) / 2
            let handScreenPoint = CGPoint(
                x: CGFloat(avgX) * arView.frame.width,
                y: (1 - CGFloat(avgY)) * arView.frame.height
            )
            
            // If a tool has been selected.
            if let toolName = selectedTool.wrappedValue {
                // If the selected tool has changed, remove the existing tool entity.
                if currentToolName != toolName {
                    if let existingTool = toolEntity, existingTool.parent != nil {
                        existingTool.removeFromParent()
                    }
                    toolEntity = nil
                    currentToolName = toolName
                }
                
                // Load the tool model if not already loaded.
                if toolEntity == nil {
                    Task {
                        if toolName == "vacuum" {
                            await MainActor.run {
                                let suctionTip = ModelEntity(
                                    mesh: .generateCylinder(height: 0.1, radius: 0.005),
                                    materials: [SimpleMaterial(color: .gray, isMetallic: true)]
                                )
                                let handle = ModelEntity(
                                    mesh: .generateCylinder(height: 0.08, radius: 0.01),
                                    materials: [SimpleMaterial(color: .darkGray, isMetallic: true)]
                                )
                                suctionTip.position = SIMD3<Float>(0, 0.09, 0)
                                handle.position = SIMD3<Float>(0, 0.04, 0)
                                let vacuumEntity = Entity()
                                vacuumEntity.addChild(handle)
                                vacuumEntity.addChild(suctionTip)
                                vacuumEntity.generateCollisionShapes(recursive: true)
                                self.toolEntity = vacuumEntity
                            }
                        } else if toolName == "scalpel" {
                            if let fileURL = Bundle.main.url(forResource: "Scalpel 1", withExtension: "usdc") {
                                do {
                                    let scalpelEntity = try await ModelEntity.loadModel(contentsOf: fileURL)
                                    
                                    // First: 90° Y-axis rotation
                                    let yRotation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
                                    // Then: 20° X-axis tilt (forward/downward)
                                    let xTilt = simd_quatf(angle: .pi / 9, axis: [1, 0, 0])  // pi/9 ≈ 20°
                                    
                                    scalpelEntity.transform.rotation = simd_mul(yRotation, xTilt)
                                    
                                    // Scale down
                                    scalpelEntity.scale = SIMD3<Float>(repeating: 0.7)
                                    
                                    self.toolEntity = scalpelEntity
                                    
                                } catch {
                                    print("❌ Scalpel model loading failed: \(error)")
                                }
                            } else {
                                print("❌ Scalpel model file not found.")
                            }
                        } else if toolName == "tweezer" {
                            // For tweezers, we don't load any model - just use natural hands
                            print("✅ Tweezer selected - using natural hand gestures without a model")
                            // Set a dummy entity to mark selection as complete
                            await MainActor.run {
                                // Create an invisible entity as a placeholder for tweezers
                                let dummyEntity = Entity()
                                self.toolEntity = dummyEntity
                            }
                        }
                        // Add the tool to the scene if not already attached.
                        if let arView = self.arView, let toolEntity = self.toolEntity, toolEntity.parent == nil {
                            // Don't add the entity to the scene for tweezers
                            if toolName != "tweezer" {
                                let toolAnchor = AnchorEntity(world: [0, 0, 0])
                                toolAnchor.addChild(toolEntity)
                                arView.scene.addAnchor(toolAnchor)
                            }
                        }
                    }
                    // Wait until the tool is loaded.
                    return
                }
                
                // Since a pinch is active, always update the tool's position to your hand's coordinates.
                if toolGrabbed, let toolEntity = self.toolEntity {
                    // Skip position updates for tweezer as it doesn't have a visual model
                    if toolName != "tweezer" {
                        // Perform a hit-test to translate the hand's screen point to a real-world coordinate.
                        let hitTestResults = arView.hitTest(handScreenPoint, types: .featurePoint)
                        if let hitResult = hitTestResults.first {
                            let worldPosition = hitResult.worldTransform.columns.3
                            let cameraTransform = currentFrame.camera.transform
                            let cameraPosition = SIMD3<Float>(cameraTransform.columns.3.x,
                                                              cameraTransform.columns.3.y,
                                                              cameraTransform.columns.3.z)
                            let hitWorldPos = SIMD3<Float>(worldPosition.x, worldPosition.y, worldPosition.z)
                            let direction = simd_normalize(hitWorldPos - cameraPosition)
                            let newPosition = cameraPosition + direction * fixedDepth
                            
                            if let parent = toolEntity.parent {
                                let localPosition = parent.convert(position: newPosition, from: nil)
                                let moveTransform = Transform(
                                    scale: toolEntity.transform.scale,
                                    rotation: toolEntity.transform.rotation,
                                    translation: localPosition
                                )
                                toolEntity.move(to: moveTransform, relativeTo: parent, duration: 0.1)
                            } else {
                                let moveTransform = Transform(
                                    scale: toolEntity.transform.scale,
                                    rotation: toolEntity.transform.rotation,
                                    translation: newPosition
                                )
                                toolEntity.move(to: moveTransform, relativeTo: nil, duration: 0.1)
                            }
                        }
                    }
                }
                
                // --- Collision Detection for Vacuum Tool (updated) ---
                // Only allow the countdown if the tumour has not yet been replaced.
                if toolName == "vacuum", let vacuum = toolEntity, let tumour = tumourEntity, !tumourReplaced {
                    if isColliding(vacuum, tumour) {
                        // Start the countdown if not already running.
                        if !collisionCountdownActive {
                            startCountdown()
                        }
                    } else {
                        // If collision ends during the countdown, stop and reset it.
                        if collisionCountdownActive {
                            stopCountdown()
                        }
                    }
                }
                
                // --- Scalpel precision scoring when green ring is present
                if toolName == "scalpel", 
                   let scalpel = toolEntity, 
                   let ring = tumourSphereEntity, 
                   tumourReplaced {  // Only active when hollow tumor and ring are visible
                    
                    // Check for first collision to start scoring
                    if isColliding(scalpel, ring) && !scalpelPrecisionScoreActive {
                        // First contact with ring, start the scoring system
                        startScalpelPrecisionScoring()
                    }
                    
                    // Track scalpel position for scoring updates (separate from initial start)
                    if scalpelPrecisionScoreActive && scalpelTrackingTimer == nil {
                        startScalpelPositionTracking(scalpel: scalpel, ring: ring)
                    }
                }
                
                // Special handling for tweezers - use hand position directly for collision detection
                if toolName == "tweezer" && toolGrabbed {
                    // When using tweezers (hands only) and pinching, check if the pinch point is near the tumor
                    if let tumour = tumourEntity, !tumourReplaced {
                        // Convert hand screen point to world coordinates for collision detection
                        let hitTestResults = arView.hitTest(handScreenPoint, types: .featurePoint)
                        if let hitResult = hitTestResults.first {
                            let pinchWorldPosition = hitResult.worldTransform.columns.3
                            let pinchPosition = SIMD3<Float>(pinchWorldPosition.x, pinchWorldPosition.y, pinchWorldPosition.z)
                            
                            // Check if the pinch is close to the tumour (using a custom distance check)
                            let tumourBounds = tumour.visualBounds(relativeTo: nil)
                            let tumourCenter = (tumourBounds.min + tumourBounds.max) / 2
                            let distance = simd_distance(pinchPosition, tumourCenter)
                            
                            // If the pinch is close enough to the tumour, consider it a collision
                            if distance < 0.1 { // Adjust threshold as needed
                                print("👌 Tweezers (pinch) colliding with tumour")
                                // Handle any special tweezer behavior here
                            }
                        }
                    }
                    
                    // Check if tweezers (hand pinch) is interacting with the green ring
                    if let ring = tumourSphereEntity, tumourReplaced {
                        // Process tweezers interaction with the green ring
                        let hitTestResults = arView.hitTest(handScreenPoint, types: .featurePoint)
                        if let hitResult = hitTestResults.first {
                            let pinchWorldPosition = hitResult.worldTransform.columns.3
                            let pinchPosition = SIMD3<Float>(pinchWorldPosition.x, pinchWorldPosition.y, pinchWorldPosition.z)
                            
                            // Check if pinch is near the green ring
                            let ringBounds = ring.visualBounds(relativeTo: nil)
                            let ringCenter = (ringBounds.min + ringBounds.max) / 2
                            let distance = simd_distance(pinchPosition, ringCenter)
                            
                            // If close enough to the ring, treat as collision for scoring
                            if distance < 0.2 && !scalpelPrecisionScoreActive { // Larger threshold for the ring
                                // Start the precision scoring as if it were a scalpel
                                startScalpelPrecisionScoring()
                            }
                            
                            // Once scoring has started, track position similar to scalpel
                            if scalpelPrecisionScoreActive && scalpelTrackingTimer == nil {
                                // Create a dummy entity at pinch position for tracking
                                let dummyEntity = Entity()
                                startScalpelPositionTracking(scalpel: dummyEntity, ring: ring)
                                
                                // Update the tracking function to use pinch position
                                scalpelTrackingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                                    guard let self = self,
                                          self.scalpelTimeRemaining > 0,
                                          self.scalpelPrecisionScoreActive else { return }
                                    
                                    // Check if pinch is near the ring
                                    let hitTestResults = arView.hitTest(handScreenPoint, types: .featurePoint)
                                    if let hitResult = hitTestResults.first {
                                        let pinchWorldPosition = hitResult.worldTransform.columns.3
                                        let pinchPosition = SIMD3<Float>(pinchWorldPosition.x, pinchWorldPosition.y, pinchWorldPosition.z)
                                        let isInside = simd_distance(pinchPosition, ringCenter) < 0.2
                                        
                                        DispatchQueue.main.async {
                                            if isInside {
                                                // Inside the ring: increase score with multiplier
                                                let increase = min(self.scalpelMultiplier, 100 - self.currentScore)
                                                self.currentScore = min(100, self.currentScore + increase)
                                                self.scalpelMultiplier = min(32, self.scalpelMultiplier * 2)
                                            } else {
                                                // Outside the ring: decrease score
                                                let decrease = min(self.scalpelMultiplier, self.currentScore)
                                                self.currentScore = max(0, self.currentScore - decrease)
                                                self.scalpelMultiplier = 1
                                            }
                                            
                                            // Update the score UI
                                            self.scalpelPrecisionScore.wrappedValue = self.currentScore
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    // New feature: Handle hollow tumour grabbing with tweezers after precision challenge
                    if scalpelPrecisionCompleted, let tumour = tumourEntity, tumourReplaced {
                        // Get pinch position in world coordinates
                        let hitTestResults = arView.hitTest(handScreenPoint, types: .featurePoint)
                        if let hitResult = hitTestResults.first {
                            let pinchWorldPosition = hitResult.worldTransform.columns.3
                            let pinchPosition = SIMD3<Float>(pinchWorldPosition.x, pinchWorldPosition.y, pinchWorldPosition.z)
                            
                            // Get tumour position
                            let tumourBounds = tumour.visualBounds(relativeTo: nil)
                            let tumourCenter = (tumourBounds.min + tumourBounds.max) / 2
                            let distance = simd_distance(pinchPosition, tumourCenter)
                            
                            // If not already grabbed, check if pinch is close enough to grab
                            if !hollowTumourGrabbed {
                                if distance < tumourGrabThreshold {
                                    hollowTumourGrabbed = true
                                    print("✅ Hollow tumour grabbed with tweezers")
                                    
                                    // Optional: Play a haptic feedback or sound
                                    let generator = UIImpactFeedbackGenerator(style: .medium)
                                    generator.impactOccurred()
                                }
                            }
                            
                            // If tumour is grabbed, move it to follow the pinch position
                            if hollowTumourGrabbed {
                                // Get the camera's position
                                let cameraTransform = currentFrame.camera.transform
                                let cameraPosition = SIMD3<Float>(cameraTransform.columns.3.x,
                                                                  cameraTransform.columns.3.y,
                                                                  cameraTransform.columns.3.z)
                                
                                // Calculate ray direction and position along ray
                                if let ray = arView.ray(through: handScreenPoint) {
                                    // Calculate new position based on hand position and fixed depth
                                    let newPosition = cameraPosition + ray.direction * fixedDepth
                                    
                                    // Move the tumour to the new position
                                    if let parent = tumour.parent {
                                        let localPosition = parent.convert(position: newPosition, from: nil)
                                        tumour.move(to: Transform(scale: tumour.scale,
                                                                  rotation: tumour.orientation,
                                                                  translation: localPosition),
                                                    relativeTo: parent,
                                                    duration: 0.1)
                                        
                                        // Check distance from original position
                                        let parentPosition = parent.position(relativeTo: nil)
                                        let worldPosition = parent.convert(position: localPosition, to: nil)
                                        let distanceFromParent = simd_distance(parentPosition, worldPosition)
                                        
                                        // If moved far enough from the brain, detach it completely
                                        if distanceFromParent > 0.3 { // Adjust threshold as needed
                                            // Detach from parent and create a new anchor
                                            detachTumourFromBrain(tumour: tumour, newPosition: worldPosition)
                                        }
                                    } else {
                                        tumour.move(to: Transform(scale: tumour.scale,
                                                                  rotation: tumour.orientation,
                                                                  translation: newPosition),
                                                    relativeTo: nil,
                                                    duration: 0.1)
                                    }
                                    
                                    // Add visual feedback that tumour is being grabbed (glow effect)
                                    if tumour.components[ModelComponent.self]?.materials.count ?? 0 > 0 {
                                        // Highlight the tumour with a glow while grabbed
                                        for i in 0..<(tumour.components[ModelComponent.self]?.materials.count ?? 0) {
                                            if var material = tumour.components[ModelComponent.self]?.materials[i] as? SimpleMaterial {
                                                material.color = .init(tint: .white, texture: nil)
                                                material.metallic = 0.8
                                                material.roughness = 0.2
                                                tumour.components[ModelComponent.self]?.materials[i] = material
                                            }
                                        }
                                    }
                                }
                            } else {
                                // Reset material when not grabbed
                                if let tumour = tumourEntity, 
                                   tumour.components[ModelComponent.self]?.materials.count ?? 0 > 0 {
                                    for i in 0..<(tumour.components[ModelComponent.self]?.materials.count ?? 0) {
                                        if var material = tumour.components[ModelComponent.self]?.materials[i] as? SimpleMaterial {
                                            material.color = .init(tint: .gray, texture: nil)
                                            material.metallic = 0.3
                                            material.roughness = 0.7
                                            tumour.components[ModelComponent.self]?.materials[i] = material
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        /// Start the scalpel precision scoring timer
        func startScalpelPrecisionScoring() {
            // Initialize the score
            currentScore = 100
            scalpelMultiplier = 1
            scalpelTimeRemaining = 10
            scalpelPrecisionScoreActive = true
            
            // Update the UI with initial score
            DispatchQueue.main.async {
                self.scalpelPrecisionScore.wrappedValue = self.currentScore
            }
            
            // Create a timer that counts down from 10 seconds
            scalpelScoreTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                guard let self = self else { return }
                
                // Decrease time remaining
                self.scalpelTimeRemaining -= 1
                
                if self.scalpelTimeRemaining <= 0 {
                    // Time's up, stop the timer
                    timer.invalidate()
                    self.scalpelScoreTimer = nil
                    
                    // Stop position tracking
                    self.scalpelTrackingTimer?.invalidate()
                    self.scalpelTrackingTimer = nil
                    
                    // Remove the green ring as it's no longer needed
                    if let ring = self.tumourSphereEntity {
                        DispatchQueue.main.async {
                            ring.removeFromParent()
                            self.tumourSphereEntity = nil
                        }
                    }
                    
                    // Mark the precision challenge as completed so the hollow tumour can be grabbed
                    self.scalpelPrecisionCompleted = true
                    print("✅ Scalpel precision challenge completed - hollow tumour can now be grabbed with tweezers")
                    
                    // Show a message to indicate tweezers can be used now
                    if let tumour = self.tumourEntity {
                        // Get the world position directly (not optional)
                        let worldPosition = tumour.position(relativeTo: nil)
                        
                        DispatchQueue.main.async {
                            // Display a hint that tweezers can now be used
                            self.showARText(text: "Use Tweezers to Remove Tumour", 
                                            at: worldPosition, 
                                            color: .orange)
                        }
                        
                        // Make the tumour pulse briefly to attract attention
                        let originalScale = tumour.scale
                        
                        // Repeat pulse effect a few times using transform animations instead of ScaleAction
                        for i in 0..<3 {
                            DispatchQueue.main.asyncAfter(deadline: .now() + (Double(i) * 1.1)) {
                                // Scale up
                                tumour.scale = originalScale
                                tumour.move(to: Transform(scale: originalScale * 1.2, 
                                                          rotation: tumour.orientation, 
                                                          translation: tumour.position), 
                                            relativeTo: tumour.parent, duration: 0.5)
                                
                                // Scale down
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    tumour.move(to: Transform(scale: originalScale, 
                                                             rotation: tumour.orientation, 
                                                             translation: tumour.position), 
                                               relativeTo: tumour.parent, duration: 0.5)
                                }
                            }
                        }
                    }
                    
                    // Keep the final score visible for a while, then fade it out
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        // Fade out the score display after 3 more seconds
                        withAnimation(.easeOut(duration: 1.0)) {
                            self.scalpelPrecisionScore.wrappedValue = nil
                        }
                    }
                    
                    print("✅ Scalpel precision challenge completed with score: \(self.currentScore)%")
                }
            }
        }
        
        /// Track the scalpel position relative to the ring for continuous scoring
        func startScalpelPositionTracking(scalpel: Entity, ring: Entity) {
            // Create a timer that checks position every 0.5 seconds
            scalpelTrackingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self = self,
                      self.scalpelTimeRemaining > 0,
                      self.scalpelPrecisionScoreActive else { return }
                
                // Check if scalpel is inside the ring
                let isInside = self.isColliding(scalpel, ring)
                
                DispatchQueue.main.async {
                    if isInside {
                        // Inside the ring: increase score with multiplier (doubling each second)
                        let increase = min(self.scalpelMultiplier, 100 - self.currentScore)
                        self.currentScore = min(100, self.currentScore + increase)
                        
                        // Double the multiplier for next time (up to a reasonable limit)
                        self.scalpelMultiplier = min(32, self.scalpelMultiplier * 2)
                    } else {
                        // Outside the ring: decrease score with same multiplier
                        let decrease = min(self.scalpelMultiplier, self.currentScore)
                        self.currentScore = max(0, self.currentScore - decrease)
                        
                        // Reset multiplier when outside
                        self.scalpelMultiplier = 1
                    }
                    
                    // Update the score UI
                    self.scalpelPrecisionScore.wrappedValue = self.currentScore
                }
            }
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let arView = gesture.view as? ARView else { return }
            let location = gesture.location(in: arView)
            
            if brainPlaced {
                gesture.isEnabled = false
                print("✅ Brain placement disabled after second tap.")
                return
            }
            
            if let result = arView.raycast(from: location, allowing: .existingPlaneGeometry, alignment: .horizontal).first {
                let transform = result.worldTransform
                
                Task {
                    let fileName = "brain"
                    let fileExtension = "usdc"
                    guard let fileURL = Bundle.main.url(forResource: fileName, withExtension: fileExtension) else {
                        print("❌ \(fileName).\(fileExtension) not found.")
                        return
                    }
                    
                    do {
                        let brainEntity = try await ModelEntity.loadModel(contentsOf: fileURL)
                        brainEntity.scale = SIMD3<Float>(repeating: 0.03)
                        brainEntity.position = [0, 0.05, 0]
                        
                        let cubeFileName = "Tumor"
                        let cubeFileExtension = "usdc"
                        if let cubeFileURL = Bundle.main.url(forResource: cubeFileName, withExtension: cubeFileExtension) {
                            do {
                                let tumourEntity = try await ModelEntity.loadModel(contentsOf: cubeFileURL)
                                tumourEntity.scale = SIMD3<Float>(repeating: 0.05)
                                tumourEntity.position = [0, 0.1, 8]
                                tumourEntity.generateCollisionShapes(recursive: true)
                                brainEntity.addChild(tumourEntity)
                                print("✅ Tumour cube added as child of brain.")
                                self.tumourEntity = tumourEntity
                                // Reset the replacement flag for a new placement.
                                self.tumourReplaced = false
                                
                            } catch {
                                print("❌ Tumour cube model loading failed: \(error)")
                            }
                        } else {
                            print("❌ Tumour cube model file \(cubeFileName).\(cubeFileExtension) not found.")
                        }
                        
                        let anchor = AnchorEntity(world: transform)
                        anchor.addChild(brainEntity)
                        arView.scene.addAnchor(anchor)
                        print("✅ Brain model loaded and anchored at tap location.")
                        self.brainPlaced = true
                    } catch {
                        print("❌ Brain model loading failed: \(error)")
                    }
                }
            } else {
                print("No horizontal surface found at tap location.")
            }
        }
        
        /// Check collision by comparing visual bounding boxes.
        func isColliding(_ entityA: Entity, _ entityB: Entity) -> Bool {
            let boundsA = entityA.visualBounds(relativeTo: nil)
            let boundsB = entityB.visualBounds(relativeTo: nil)
            
            return (boundsA.max.x > boundsB.min.x && boundsA.min.x < boundsB.max.x) &&
                   (boundsA.max.y > boundsB.min.y && boundsA.min.y < boundsB.max.y) &&
                   (boundsA.max.z > boundsB.min.z && boundsA.min.z < boundsB.max.z)
        }
        
        /// Starts a 6‑second countdown and updates the SwiftUI binding.
        /// When the countdown hits 0, we immediately mark the tumour as replaced to prevent restart.
        func startCountdown() {
            collisionCountdownActive = true
            DispatchQueue.main.async {
                self.collisionCountdown.wrappedValue = 6
            }
            countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    if let current = self.collisionCountdown.wrappedValue, current > 0 {
                        self.collisionCountdown.wrappedValue = current - 1
                    } else {
                        timer.invalidate()
                        self.countdownTimer = nil
                        self.collisionCountdown.wrappedValue = nil
                        self.collisionCountdownActive = false
                        // Mark the tumour as replaced immediately so that no new countdown starts.
                        self.tumourReplaced = true
                        self.replaceTumourModel()
                    }
                }
            }
        }
        
        /// Stops the countdown timer and resets the countdown state.
        func stopCountdown() {
            countdownTimer?.invalidate()
            countdownTimer = nil
            collisionCountdownActive = false
            DispatchQueue.main.async {
                self.collisionCountdown.wrappedValue = nil
            }
        }
        
        /// Replaces the current tumour model with the hollow tumour model at the same coordinates.
        func replaceTumourModel() {
            guard let oldTumour = self.tumourEntity, let parent = oldTumour.parent else { return }
            let oldTransform = oldTumour.transform
            Task {
                if let fileURL = Bundle.main.url(forResource: "hollow_tumour", withExtension: "usdc") {
                    do {
                        let newTumour = try await ModelEntity.loadModel(contentsOf: fileURL)
                        newTumour.scale = oldTumour.scale
                        newTumour.generateCollisionShapes(recursive: true)
                        
                        // Rotate 90° to the left around Y-axis
                        let rotation = simd_quatf(angle: -.pi / 2, axis: [0, 1, 0])
                        newTumour.transform = Transform(
                            scale: oldTransform.scale,
                            rotation: rotation * oldTransform.rotation,
                            translation: oldTransform.translation
                        )
                        
                        DispatchQueue.main.async {
                            oldTumour.removeFromParent()
                            parent.addChild(newTumour)
                            self.tumourEntity = newTumour
                            print("✅ Tumour replaced with hollow tumour model at the same coordinates and rotated 90° left.")
                            
                            // Add the green ring only after the hollow tumour has been placed
                            // Remove any existing ring if present
                            if let oldRing = self.tumourSphereEntity {
                                oldRing.removeFromParent()
                            }
                            
                            let ringMesh = MeshResource.generateCylinder(height: 0.05, radius: 2)
                            let greenMaterial = SimpleMaterial(color: .green, isMetallic: false)
                            let ringEntity = ModelEntity(mesh: ringMesh, materials: [greenMaterial])
                            
                            // Position the ring exactly where the hollow tumour is
                            ringEntity.position = newTumour.position
                            ringEntity.position.z += 0.7  // Slight vertical offset
                            ringEntity.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])  // Lay the ring flat
                            
                            // Need to generate collision shapes to detect scalpel intersection
                            ringEntity.generateCollisionShapes(recursive: true)
                            
                            parent.addChild(ringEntity)
                            self.tumourSphereEntity = ringEntity
                            print("✅ Green ring added around the hollow tumour.")
                            
                            // Reset any existing scalpel scoring
                            self.scalpelPrecisionScoreActive = false
                            self.scalpelScoreTimer?.invalidate()
                            self.scalpelScoreTimer = nil
                            self.scalpelTrackingTimer?.invalidate()
                            self.scalpelTrackingTimer = nil
                            self.scalpelPrecisionScore.wrappedValue = nil
                        }
                    } catch {
                        print("❌ Failed to load hollow tumour model: \(error)")
                    }
                } else {
                    print("❌ hollow_tumour.usdc not found in bundle.")
                }
            }
        }
        
        /// Detaches the tumour from the brain and creates a new anchor in the world
        func detachTumourFromBrain(tumour: Entity, newPosition: SIMD3<Float>) {
            guard let parent = tumour.parent, let arView = self.arView else { return }
            
            // Remember the position for showing text
            let positionForText = newPosition
            
            // Remove the tumour from its parent
            tumour.removeFromParent()
            
            // No need to create a new anchor or reattach the tumor
            // The tumor simply disappears as requested
            
            print("✅ Hollow tumour successfully detached and removed from scene")
            
            // Play a success sound or haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
            // Show the success message
            DispatchQueue.main.async {
                // Skip the animation and just set the state directly
                self.showTumourExtractedMessage.wrappedValue = true
            }
            
            // Show a text overlay indicating success
            DispatchQueue.main.async {
                // Create a temporary floating text in AR space
                self.showARText(text: "Tumour Successfully Removed!", at: positionForText, color: .green)
            }
            
            // Optional: Add a particle effect at the position where the tumor was
            addDisappearanceEffect(at: positionForText)
        }
        
        /// Adds a particle effect at the given position to emphasize the tumor disappearance
        func addDisappearanceEffect(at position: SIMD3<Float>) {
            guard let arView = arView else { return }
            
            // Create small particles that will expand outward
            for _ in 0..<10 {
                // Create small sphere for particle
                let particle = ModelEntity(
                    mesh: .generateSphere(radius: 0.01),
                    materials: [SimpleMaterial(color: .white, isMetallic: true)]
                )
                
                // Random direction for particle
                let randomVector = SIMD3<Float>(
                    Float.random(in: -1...1),
                    Float.random(in: -1...1),
                    Float.random(in: -1...1)
                )
                
                // Manually normalize the vector
                let length = sqrt(randomVector.x * randomVector.x + 
                                 randomVector.y * randomVector.y + 
                                 randomVector.z * randomVector.z)
                let randomDirection = length > 0 ? 
                    SIMD3<Float>(randomVector.x / length, 
                                randomVector.y / length, 
                                randomVector.z / length) : 
                    SIMD3<Float>(0, 1, 0) // Default to up if zero vector
                
                // Position at the disappearance spot
                let particleAnchor = AnchorEntity(world: position)
                particleAnchor.addChild(particle)
                arView.scene.addAnchor(particleAnchor)
                
                // Move outward and fade
                let distance: Float = 0.2
                let duration: TimeInterval = 0.5
                
                // Move outward
                let endPosition = particle.position + (randomDirection * distance)
                particle.move(
                    to: Transform(scale: .zero, rotation: particle.orientation, translation: endPosition),
                    relativeTo: particleAnchor,
                    duration: duration
                )
                
                // Remove after animation
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                    particleAnchor.removeFromParent()
                }
            }
        }
        
        /// Shows temporary text in AR space
        func showARText(text: String, at position: SIMD3<Float>, color: UIColor) {
            guard let arView = arView else { return }
            
            // Create a text mesh
            let textMesh = MeshResource.generateText(
                text,
                extrusionDepth: 0.01,
                font: .systemFont(ofSize: 0.1),
                containerFrame: .zero,
                alignment: .center,
                lineBreakMode: .byTruncatingTail
            )
            
            // Create material with the specified color
            let material = SimpleMaterial(color: color, isMetallic: false)
            
            // Create text entity
            let textEntity = ModelEntity(mesh: textMesh, materials: [material])
            
            // Position it slightly above where the tumour was extracted
            var textPosition = position
            textPosition.y += 0.1
            
            // Make the text face the camera
            if let cameraTransform = arView.session.currentFrame?.camera.transform {
                let cameraPosition = SIMD3<Float>(cameraTransform.columns.3.x,
                                                 cameraTransform.columns.3.y,
                                                 cameraTransform.columns.3.z)
                textEntity.look(at: cameraPosition, from: textPosition, relativeTo: nil)
            }
            
            // Create anchor and add to scene
            let textAnchor = AnchorEntity(world: textPosition)
            textAnchor.addChild(textEntity)
            arView.scene.addAnchor(textAnchor)
            
            // Start with small scale and animate to full size
            textEntity.scale = SIMD3<Float>(repeating: 0.001)
            textEntity.move(to: Transform(scale: SIMD3<Float>(repeating: 1.0), 
                                          rotation: textEntity.orientation, 
                                          translation: textEntity.position), 
                            relativeTo: textAnchor, 
                            duration: 0.3)
            
            // Remove after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                // Fade out using simplified approach - just remove after delay
                // We can't easily animate the alpha, so just remove it
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    textAnchor.removeFromParent()
                }
            }
        }
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            // Not used because hand tracking is handled by our timer.
        }
        
        deinit {
            handTrackingTimer?.invalidate()
            countdownTimer?.invalidate()
            scalpelScoreTimer?.invalidate()
            scalpelTrackingTimer?.invalidate()
        }
    }
}

// Custom animation modifiers for the landing page
struct FloatingAnimation: ViewModifier {
    let duration: Double
    let yOffset: CGFloat
    
    @State private var isAnimating = false
    
    func body(content: Content) -> some View {
        content
            .offset(y: isAnimating ? yOffset : 0)
            .animation(
                Animation.easeInOut(duration: duration)
                    .repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

struct PulsatingOpacity: ViewModifier {
    let minOpacity: Double
    let maxOpacity: Double
    let duration: Double
    
    @State private var isAnimating = false
    
    func body(content: Content) -> some View {
        content
            .opacity(isAnimating ? maxOpacity : minOpacity)
            .animation(
                Animation.easeInOut(duration: duration)
                    .repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

struct PulsatingScale: ViewModifier {
    let minScale: CGFloat
    let maxScale: CGFloat
    let duration: Double
    
    @State private var isAnimating = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isAnimating ? maxScale : minScale)
            .animation(
                Animation.easeInOut(duration: duration)
                    .repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

struct ShimmerEffect: ViewModifier {
    @State private var isAnimating = false
    
    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [
                        .white.opacity(0.0),
                        .white.opacity(0.2),
                        .white.opacity(0.0),
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .rotationEffect(.degrees(70))
                .offset(x: isAnimating ? 400 : -400)
                .animation(
                    Animation.linear(duration: 3)
                        .repeatForever(autoreverses: false),
                    value: isAnimating
                )
                .mask(content)
                .onAppear {
                    isAnimating = true
                }
            )
    }
}

struct TypewriterText: ViewModifier {
    let text: String
    let duration: Double
    
    @State private var displayedText = ""
    @State private var isVisible = false
    
    func body(content: Content) -> some View {
        // Hide original content and show our animated version instead
        content
            .opacity(0)
            .overlay(
                Text(displayedText)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .opacity(isVisible ? 1 : 0)
            )
            .onAppear {
                // Add a slight delay before starting
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // Make text visible
                    withAnimation { isVisible = true }
                    
                    // Animated typing effect
                    let baseTime = duration / Double(text.count)
                    for (index, _) in text.enumerated() {
                        DispatchQueue.main.asyncAfter(deadline: .now() + baseTime * Double(index) + 0.5) {
                            displayedText = String(text.prefix(index + 1))
                        }
                    }
                }
            }
    }
}

extension View {
    var modifierDescription: String {
        let mirror = Mirror(reflecting: self)
        return mirror.children.first?.label ?? String(describing: self)
    }
}

// MARK: - Preview
// Uncomment the following if you wish to see a preview.
// struct ContentView_Previews: PreviewProvider {
//     static var previews: some View {
//         ContentView()
//     }
// }
