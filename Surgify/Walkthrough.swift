//
//  Walkthrough.swift
//  Surgify
//
//  Created by Yash Aggarwal on 11/04/25.
//

import SwiftUI
import RealityKit
import ARKit
import Combine

// MARK: - WalkthroughARView

struct WalkthroughARView: View {
    @State private var spacing: Float = 0.15    // Initial spacing between cubes (meters)
    @State private var focusedCube: Entity? = nil
    @State private var cubeOriginalTransforms: [Entity: Transform] = [:] // To store original positions
    
    // Coordinator instance to manage AR interactions
    @StateObject private var coordinator = WalkthroughCoordinator()
    
    var body: some View {
        ZStack(alignment: .bottom) {
            WalkthroughARViewContainer(spacing: $spacing, focusedCube: $focusedCube, cubeOriginalTransforms: $cubeOriginalTransforms, coordinator: coordinator)
                .edgesIgnoringSafeArea(.all)
            
            // SwiftUI overlays
            VStack {
                // Reset Button (only visible if a cube is focused)
                if focusedCube != nil {
                    Button("Reset View") {
                        coordinator.resetFocus()
                    }
                    .padding()
                    .background(.regularMaterial)
                    .foregroundColor(.primary)
                    .cornerRadius(10)
                    .padding(.bottom, 5)
                }
                
                // Spacing Slider (visible only if no cube is focused)
                if focusedCube == nil {
                    HStack {
                        Text("Spacing:")
                        Slider(value: $spacing, in: 0.05...0.5)
                            .padding(.horizontal)
                    }
                    .padding()
                    .background(.regularMaterial)
                    .cornerRadius(10)
                }
            }
            .padding()
        }
        .onAppear {
            coordinator.setup(spacing: spacing, focusedCube: focusedCube, cubeOriginalTransforms: cubeOriginalTransforms)
        }
        .onChange(of: spacing) { newSpacing in
            coordinator.updateSpacing(newSpacing)
        }
        .onChange(of: focusedCube) { newFocusedCube in
            coordinator.focusedCube = newFocusedCube
        }
        .onChange(of: cubeOriginalTransforms) { newTransforms in
            coordinator.cubeOriginalTransforms = newTransforms
        }
    }
}

// MARK: - WalkthroughARViewContainer (UIViewRepresentable)

struct WalkthroughARViewContainer: UIViewRepresentable {
    @Binding var spacing: Float
    @Binding var focusedCube: Entity?
    @Binding var cubeOriginalTransforms: [Entity: Transform]
    @ObservedObject var coordinator: WalkthroughCoordinator

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        coordinator.arView = arView
        coordinator.bindings = (spacing: $spacing, focusedCube: $focusedCube, cubeOriginalTransforms: $cubeOriginalTransforms)
        
        // Basic AR Configuration (World Tracking)
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        arView.session.run(configuration)
        
        // Setup scene content and gestures via coordinator
        coordinator.setupScene()
        coordinator.setupGestures()
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // Updates (if needed) handled by coordinator
    }
    
    func makeCoordinator() -> WalkthroughCoordinator {
        return coordinator
    }
}

// MARK: - WalkthroughCoordinator (Handles AR Logic)

class WalkthroughCoordinator: NSObject, ObservableObject {
    weak var arView: ARView?
    var bindings: (spacing: Binding<Float>, focusedCube: Binding<Entity?>, cubeOriginalTransforms: Binding<[Entity: Transform]>)?
    
    var gridAnchor: AnchorEntity?
    var cubeEntities: [ModelEntity] = []
    var labelEntities: [ModelEntity] = []
    var modelLoadCancellable: AnyCancellable?
    var tapGestureRecognizer: UITapGestureRecognizer?
    
    // Internal state
    @Published var spacing: Float = 0.15
    @Published var focusedCube: Entity? = nil
    @Published var cubeOriginalTransforms: [Entity: Transform] = [:]
    
    private var internalCancellables = Set<AnyCancellable>()
    
    override init() {
        super.init()
        // Observe published properties to update bindings.
        $spacing
            .sink { [weak self] newSpacing in
                self?.bindings?.spacing.wrappedValue = newSpacing
                self?.updateCubePositions()
            }
            .store(in: &internalCancellables)
        
        $focusedCube
            .sink { [weak self] newFocus in
                self?.bindings?.focusedCube.wrappedValue = newFocus
            }
            .store(in: &internalCancellables)
        
        $cubeOriginalTransforms
            .sink { [weak self] newTransforms in
                self?.bindings?.cubeOriginalTransforms.wrappedValue = newTransforms
            }
            .store(in: &internalCancellables)
    }
    
    // Called from WalkthroughARView.onAppear
    func setup(spacing: Float, focusedCube: Entity?, cubeOriginalTransforms: [Entity: Transform]) {
        self.spacing = spacing
        self.focusedCube = focusedCube
        self.cubeOriginalTransforms = cubeOriginalTransforms
    }
    
    // Update spacing changes (cube positions updated automatically)
    func updateSpacing(_ newSpacing: Float) {
        guard self.spacing != newSpacing else { return }
        self.spacing = newSpacing
    }
    
    func setupScene() {
        guard let arView = arView else { return }
        gridAnchor = AnchorEntity(world: [0, 0, -1.0]) // Place grid 1m in front
        arView.scene.addAnchor(gridAnchor!)
        
        modelLoadCancellable = ModelEntity.loadModelAsync(named: "cube.usdc")
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    print("❌ Failed to load cube.usdc: \(error)")
                }
            }, receiveValue: { [weak self] loadedModel in
                guard let self = self else { return }
                print("✅ cube.usdc loaded successfully.")
                self.createGrid(with: loadedModel)
                self.updateCubePositions()
            })
    }

    func createGrid(with baseCubeModel: ModelEntity) {
        guard cubeEntities.isEmpty else { return }

        let cubeNames = ["Midbrain", "Cerebellum", "Right Lobe", "Left Lobe"]
        let modelFilenames = ["Midbrain.usdc", "cerebellum.usdc", "Right Lobe 1.usdc", "Left Lobe 1.usdc"]

        // Define individual scales for each model
        let modelScales: [SIMD3<Float>] = [
            SIMD3<Float>(repeating: 0.12), // Midbrain
            SIMD3<Float>(repeating: 0.12), // Cerebellum
            SIMD3<Float>(repeating: 0.27), // Left Lobe
            SIMD3<Float>(repeating: 0.45)  // Right Lobe
        ]
        
        // Define individual positions for each model
        let modelPositions: [SIMD3<Float>] = [
            SIMD3<Float>(x: 0.0, y: 0.0, z: 0),   // Midbrain
            SIMD3<Float>(x: 0.0, y: 0.0, z: 0),   // Cerebellum
            SIMD3<Float>(x: 0, y: 0.0, z: 0.0),  // Left Lobe
            SIMD3<Float>(x: 0, y: 0.0, z: 0.0)   // Right Lobe
        ]

        var tempOriginalTransforms: [Entity: Transform] = [:]

        for i in 0..<4 {
            let modelName = modelFilenames[i]

            ModelEntity.loadModelAsync(named: modelName)
                .sink(receiveCompletion: { completion in
                    if case let .failure(error) = completion {
                        print("❌ Failed to load model \(modelName): \(error)")
                    }
                }, receiveValue: { [weak self] loadedModel in
                    guard let self = self else { return }
                    let cube = loadedModel
                    cube.name = cubeNames[i]
                    cube.scale = modelScales[i] // Apply specific scale
                    cube.position = modelPositions[i] // Apply specific position
                    cube.generateCollisionShapes(recursive: true)

                    // Create label
                    let labelMesh = MeshResource.generateText(
                        cubeNames[i],
                        extrusionDepth: 0.01,
                        font: .systemFont(ofSize: 0.0),
                        containerFrame: CGRect(x: 0, y: 0, width: 0.3, height: 0.1),
                        alignment: .right,
                        lineBreakMode: .byTruncatingTail
                    )
                    let labelMaterial = SimpleMaterial(color: .white, isMetallic: false)
                    let labelEntity = ModelEntity(mesh: labelMesh, materials: [labelMaterial])
                    labelEntity.name = "\(cubeNames[i]) Label"
                    labelEntity.position = SIMD3<Float>(x: modelPositions[i].x, y: modelPositions[i].y + 0.1, z: modelPositions[i].z) // Adjust label position slightly

                    self.gridAnchor?.addChild(cube)
                    self.gridAnchor?.addChild(labelEntity)

                    self.cubeEntities.append(cube)
                    self.labelEntities.append(labelEntity)

                    tempOriginalTransforms[cube] = Transform()
                    tempOriginalTransforms[labelEntity] = Transform()

                    self.cubeOriginalTransforms = tempOriginalTransforms
                    self.updateCubePositions()
                    print("✅ Loaded \(modelName) and placed in grid.")
                })
                .store(in: &internalCancellables)
        }
    }
    

    func updateCubePositions() {
        guard !cubeEntities.isEmpty else { return }
        
        let halfSpacing = spacing / 2.0
        let positions: [SIMD3<Float>] = [
            [-halfSpacing/2, -halfSpacing, 0],  // mid brain
            [halfSpacing/2, -halfSpacing, 0],   // cerebellum
            [-halfSpacing, halfSpacing, 0], // right
            [halfSpacing, halfSpacing, 0]   // left
        ]
        
        var updatedTransforms = self.cubeOriginalTransforms
        
        for (index, cube) in cubeEntities.enumerated() {
            if focusedCube != cube {
                let newTransform = Transform(scale: cube.scale, rotation: cube.orientation, translation: positions[index])
                cube.move(to: newTransform, relativeTo: gridAnchor, duration: 0.3, timingFunction: .easeInOut)
                
                if index < labelEntities.count {
                    let label = labelEntities[index]
                    var labelPosition = positions[index]
                    labelPosition.y += (cube.visualBounds(relativeTo: cube).extents.y / 2.0) + 0.03
                    let labelTransform = Transform(scale: label.scale, rotation: label.orientation, translation: labelPosition)
//                    label.move(to: labelTransform, relativeTo: gridAnchor, duration: 0.3, timingFunction: .easeInOut)
                    updatedTransforms[label] = labelTransform
                }
                updatedTransforms[cube] = newTransform
            }
        }
        self.cubeOriginalTransforms = updatedTransforms
    }
    
    func setupGestures() {
        guard let arView = arView else { return }
        tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arView.addGestureRecognizer(tapGestureRecognizer!)
        print("✅ Tap gesture recognizer added.")
    }
    
    @objc func handleTap(_ sender: UITapGestureRecognizer) {
        guard let arView = arView else { return }
        let tapLocation = sender.location(in: arView)
        
        if let tappedEntity = arView.entity(at: tapLocation) {
            // Traverse up the hierarchy to find a cube.
            func findAncestorCube(for entity: Entity?) -> ModelEntity? {
                var currentEntity = entity
                while let entity = currentEntity {
                    if let modelEntity = entity as? ModelEntity, cubeEntities.contains(modelEntity) {
                        return modelEntity
                    }
                    currentEntity = entity.parent
                }
                return nil
            }
            
            if let tappedCube = findAncestorCube(for: tappedEntity) {
                if focusedCube == tappedCube {
                    resetFocus()
                } else {
                    focus(on: tappedCube)
                }
                return
            }
        }
        
        if focusedCube != nil {
            resetFocus()
        }
    }

        // New: Brain part descriptions
        let brainDescriptions = [
            "Left Lobe": "Left Lobe\nResponsible for logical thinking, language, analytical reasoning, and math. Controls the right side of the body and is dominant in most people for speech and writing.",
            "Right Lobe": "Right Lobe\nManages creativity, spatial ability, visual imagery, and intuition. Controls the left side of the body and helps interpret visual and musical cues, facial recognition, and emotional expression.",
            "Cerebellum": "Cerebellum\nCoordinates movement, posture, balance, and motor learning. Ensures smooth, accurate physical movements and helps in learning motor skills.",
            "Midbrain": "Midbrain\nActs as a relay station for auditory and visual information and controls reflexes like eye movement. Essential for motor control, arousal (alertness), and regulating vital functions like breathing."
        ]

        // Modified: focus() to show label with description
        func focus(on targetCube: ModelEntity) {
            guard focusedCube != targetCube else { return }
            print("Focusing on: \(targetCube.name)")
            self.focusedCube = targetCube

            let focusTransform = Transform(scale: targetCube.scale * 1.2, rotation: targetCube.orientation, translation: [0, 0, 0.2])
            targetCube.move(to: focusTransform, relativeTo: gridAnchor, duration: 0.5, timingFunction: .easeInOut)

            for cube in cubeEntities where cube != targetCube {
                var awayTransform = cubeOriginalTransforms[cube] ?? cube.transform
                awayTransform.translation.z += 1.0
                awayTransform.scale = SIMD3<Float>(repeating: 0.01)
                cube.move(to: awayTransform, relativeTo: gridAnchor, duration: 0.4, timingFunction: .easeInOut)
            }

            for (index, label) in labelEntities.enumerated() {
                if let correspondingCubeIndex = cubeEntities.firstIndex(where: { label.name.contains($0.name) }),
                   cubeEntities[correspondingCubeIndex] != targetCube {
                    var labelTransform = label.transform
                    labelTransform.scale = .zero
                    label.move(to: labelTransform, relativeTo: gridAnchor, duration: 0.4)
                } else if let correspondingCubeIndex = cubeEntities.firstIndex(where: { label.name.contains($0.name) }),
                          cubeEntities[correspondingCubeIndex] == targetCube {
                    var focusedLabelTransform = label.transform
                    let worldPosition = targetCube.position(relativeTo: gridAnchor)
                    focusedLabelTransform.translation = worldPosition
                    focusedLabelTransform.translation.y += (targetCube.visualBounds(relativeTo: gridAnchor).extents.y / 2.0) * 1.2 + 0.05

                    // New: Update label text with full brain part description
                    if let newText = brainDescriptions[targetCube.name] {
                        // Generate new label with description
                        let updatedMesh = MeshResource.generateText(
                            newText,
                            extrusionDepth: 0.01,
                            font: .systemFont(ofSize: 0.02),
                            containerFrame: CGRect(x: 0, y: -1.5, width: 0.6, height: 1.0),
                            alignment: .center,
                            lineBreakMode: .byWordWrapping
                        )
                        let updatedMaterial = SimpleMaterial(color: .white, isMetallic: false)
                        let newLabel = ModelEntity(mesh: updatedMesh, materials: [updatedMaterial])
                        newLabel.name = label.name

                        // Position above the cube
                        let cubeWorldPosition = targetCube.position(relativeTo: gridAnchor)
                        let labelHeight = (targetCube.visualBounds(relativeTo: gridAnchor).extents.y / 2.0) * 1.2 + 0.05
                        newLabel.position = cubeWorldPosition + SIMD3<Float>(0, labelHeight, -0.5)
                        newLabel.transform.rotation = simd_quatf(angle: .pi, axis: [0, 1, 0]) // Flip to face forward

               

                        // Rotate label to face camera
                        if let cameraPosition = arView?.cameraTransform.translation {
                            newLabel.look(at: cameraPosition, from: newLabel.position(relativeTo: gridAnchor), relativeTo: nil)
                        }

                        // Remove old label from scene & prevent it from rendering
                        newLabel.removeFromParent()

                        // Replace in anchor + labelEntities array
                        gridAnchor?.addChild(newLabel)
                        labelEntities[index] = newLabel
                    }

                }
            }
        }
    
    
    func resetFocus() {
        guard let previouslyFocused = focusedCube else { return }
        print("Resetting focus from: \(previouslyFocused.name)")
        self.focusedCube = nil
        
        if let originalTransform = cubeOriginalTransforms[previouslyFocused] {
            previouslyFocused.move(to: originalTransform, relativeTo: gridAnchor, duration: 0.5, timingFunction: .easeInOut)
        }
        for cube in cubeEntities where cube != previouslyFocused {
            if let originalTransform = cubeOriginalTransforms[cube] {
                cube.move(to: originalTransform, relativeTo: gridAnchor, duration: 0.4, timingFunction: .easeInOut)
            }
        }
        for (index, label) in labelEntities.enumerated() {
            if let cube = cubeEntities[safe: index], let originalCubeTransform = cubeOriginalTransforms[cube] {
                var labelPosition = originalCubeTransform.translation
                labelPosition.y += (cube.visualBounds(relativeTo: cube).extents.y / 2.0) + 0.03
                let originalLabelTransform = Transform(scale: SIMD3<Float>(repeating: 1.0), rotation: label.orientation, translation: labelPosition)
            }
        }
    }
    
    deinit {
        print("WalkthroughCoordinator deinitialized")
        modelLoadCancellable?.cancel()
        if let gesture = tapGestureRecognizer {
            arView?.removeGestureRecognizer(gesture)
        }
    }
}

// MARK: - Helper Extension for Safe Array Access

extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
