//
//  ViewController.swift
//  Adventures
//
//  Created by Marek Cervinka on 10/12/2019.
//  Copyright © 2019 Marek Cervinka. All rights reserved.
//

import UIKit
import SceneKit
import ARKit
import PlacenoteSDK

class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate, PNDelegate {

    // UI views
    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet weak var welcomeScreen: UIView!
    @IBOutlet weak var destinationsView: UIView!
    
    // UI elements
    @IBOutlet weak var findWayButton: UIButton!
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var mainTitle: UILabel!
    @IBOutlet weak var logoImage: UIImageView!
    @IBOutlet weak var clappingImage: UIImageView!
    @IBOutlet weak var rotateImage: UIImageView!
    
    // Placenote variables
    private var camManager: CameraManager? = nil;
    private var ptViz: FeaturePointVisualizer? = nil;
    
    // Navigation variables
    private var isMapLoaded: Bool = false
    private var isLocalized: Bool = false
    
    private var timer: Timer?
    
    // Destinations
    private var currentDestination: Destination? = .create;
    private let destinations: [Destination: simd_float3] = [
        .create: simd_float3(x: 14.689584, y: -1.1369095, z: -6.2151027),
        .photobooth: simd_float3(x: 8.3055525, y: -1.2095335, z: 9.071517),
    ]
    
    // Points to prevent going through real objects
    private let helperPoints: [simd_float3] = [
        simd_float3(x: 4.6166325, y: -1.2144403, z: -1.6725461),
        simd_float3(x: 8.160688, y: -1.1318008, z: -5.492145),
        simd_float3(x: 7.9057364, y: -1.1094759, z: -3.1645954),
        simd_float3(x: 6.6503773, y: -1.2312996, z: 8.123864),
    ]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the view's delegate
        sceneView.delegate = self
        
        // ARKit delegate setup
        sceneView.session.delegate = self
        
        // Placenote initialization setup
        
        // Set up this view controller as a delegate
        LibPlacenote.instance.multiDelegate += self
        
        // Set up placenote's camera manager
        if let camera: SCNNode = sceneView?.pointOfView {
            camManager = CameraManager(scene: sceneView.scene, cam: camera)
        }
        
        // Placenote feature visualization
        ptViz = FeaturePointVisualizer(inputScene: sceneView.scene);
        ptViz?.enablePointcloud()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()

        // Run the view's session
        sceneView.session.run(configuration)
        
        // Show welcome message to the user
        statusLabel.text = "Welcome! Find your way around Business Academy Aarhus."
        
        // Hide irrelevant UI elements for now
        destinationsView.isHidden = true
        clappingImage.isHidden = true
        rotateImage.isHidden = true
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }
    
    @IBAction func chooseDestination(_ sender: UIButton) {
        // Assign destination based on button pressed
        switch sender.tag {
        case 1:
            currentDestination = .photobooth
            break
        case 2:
            currentDestination = .create
        default:
            currentDestination = nil
        }
        
        // Hide welcome screen
        welcomeScreen.isHidden = true
        
        // Localize user
        if isLocalized {
            onLocalized()
        } else {
            LibPlacenote.instance.startSession()
            self.statusLabel.text = "Move around and show me what you see."
            self.rotateImage.isHidden = false
        }
    }
    
    @IBAction func findWay(_ sender: Any) {
        self.welcomeScreen.isHidden = false
        self.findWayButton.isHidden = true
        self.mainTitle.isHidden = true
        self.logoImage.isHidden = true
        
        if isMapLoaded {
            showDestinations()
        }
        else {
            loadMap()
        }
    }
    
    // Load the map containing supported area from Placenote API
    func loadMap() {
        let mapId = "4cb96da8-a01f-480b-a916-3e2e8027b55d"
        
        self.statusLabel.text = "Loading destinations. Please hold on."
        
        LibPlacenote.instance.loadMap(mapId: mapId,
            downloadProgressCb: {(completed: Bool, faulted: Bool, percentage: Float) -> Void in
            if (completed) {
                self.isMapLoaded = true
                self.showDestinations()
            }
            else if (faulted) {
              self.statusLabel.text = "Map load failed. Check your API Key or your internet connection"
            }
            else {
              self.statusLabel.text = "Download map: " + percentage.description
            }
        })
    }
    
    // Show the user the list of possible destinations
    func showDestinations() {
        clappingImage.isHidden = true
        self.statusLabel.text = "Choose your destination"
        self.destinationsView.isHidden = false
    }
    
    // Place arrows on the scene from the current position to the destination
    func placeArrowsToDestination() {
        let currentPosition = LibPlacenote.instance.getPose().position()
        
        if let destination = currentDestination {
            let destinationVector = destinations[destination]!
            
            var pointsToConnect = helperPoints
            pointsToConnect.append(destinationVector)
            var a = simd_float3(x: currentPosition.x, y: -0.5, z: currentPosition.z)
            var b: simd_float3
            
            while true {
                b = getClosestVector(target: a, vectors: pointsToConnect)!
                
                let arrowPositions = generateArrowPositions(a: a, b: b)

                for position in arrowPositions {
                    placeArrow(pos: SCNVector3(position))
                }
                
                // If we connected our destination point,
                // we can skip connecting other helper points
                guard b != destinationVector else {
                    break
                }
                
                // Remove connected point to prevent duplicates,
                // reset the future point A to the current point B
                let index = pointsToConnect.firstIndex(of: b)
                pointsToConnect.remove(at: index!)
                a = b
            }
            
        }
    }
    
    // Remove all arrows from the main scene
    func removeAllArrows() {
        for node in sceneView.scene.rootNode.childNodes {
            node.removeFromParentNode()
        }
    }
    
    // Place an arrow into the scene based on a position
    func placeArrow(pos: SCNVector3) {
        let geometry: SCNGeometry = SCNTorus(ringRadius: 0.1, pipeRadius: 0.025)
        let geometryNode = SCNNode(geometry: geometry)
        geometryNode.position = pos
        geometryNode.geometry?.firstMaterial?.diffuse.contents = UIColor.green
        
        sceneView.scene.rootNode.addChildNode(geometryNode)
    }
    
    // Choose the vector closest to the target from a list of vectors
    func getClosestVector(target: simd_float3, vectors: [simd_float3]) -> simd_float3? {
        return vectors.min {a, b in simd_distance_squared(a, target) < simd_distance_squared(b, target)}
    }
    
    // Generate list of arrow positions between A to B, placing an arrow every 0.5
    func generateArrowPositions(a: simd_float3, b: simd_float3) -> [simd_float3] {
        var positionList: [simd_float3] = []
        let arrowsCount = Int(simd_distance(a, b) / 0.5)
        let direction = b - a
        
        for i in 1...arrowsCount {
            let coeficient = Float(i) / Float(arrowsCount)
            let position = a + coeficient * direction
            positionList.append(position)
        }
        
        return positionList
    }
    
    // Hide arrows that are too far from the user
    func hideFarArrows() {
        let currentPosition = LibPlacenote.instance.getPose().position()
        let positionVector = simd_float3(x: currentPosition.x, y: currentPosition.y, z: currentPosition.z)
        
        for node in sceneView.scene.rootNode.childNodes {
            let nodePositionVector = node.simdPosition
            let isFar = simd_distance(nodePositionVector, positionVector) > 2.5
            
            SCNTransaction.animationDuration = 0.5
            node.opacity = isFar ? 0 : 1
        }
    }
    
    // Check whether the user's reached the destination,
    // if so, remove all arrows, show a message and allow to choose new destination
    func hasReachedDestination() -> Bool {
        let currentPosition = LibPlacenote.instance.getPose().position()
        let positionVector = simd_float3(x: currentPosition.x, y: currentPosition.y, z: currentPosition.z)
        let destVect = destinations[currentDestination!]!
        
        if simd_distance(destVect, positionVector) < 1.5 {
            removeAllArrows()
            
            statusLabel.text = "Hooray, you have reached your destination!"
            clappingImage.isHidden = false
            findWayButton.isHidden = false
            
            return true
        }
        else {
            return false
        }
    }


    // MARK: - PNDelegate
    
    func onPose(_ outputPose: matrix_float4x4, _ arkitPose: matrix_float4x4) {}
    
    func onStatusChange(_ prevStatus: LibPlacenote.MappingStatus, _ currStatus: LibPlacenote.MappingStatus) {}
    
    // The first localization event for loading assets
    func onLocalized() {
        isLocalized = true
        rotateImage.isHidden = true
        statusLabel.text = "Follow the rings. Happy wayfinding!"
        
        startNavigation()
    }
    
    func startNavigation() {
        placeArrowsToDestination()
        
        // Shedule repeating timer to continuously check how far arrows are and hide those far away
        timer = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(fireTimer), userInfo: nil, repeats: true)
        timer?.tolerance = 0.2
    }
    
    @objc func fireTimer() {
        guard !hasReachedDestination() else {
            timer?.invalidate()
            return
        }
        hideFarArrows()
    }
    
    
    // MARK: - ARSCNViewDelegate
    
    // send AR frame to placenote
    func session(_ session: ARSession, didUpdate: ARFrame) {
        LibPlacenote.instance.setARFrame(frame: didUpdate)
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        statusLabel.text = "Sorry, your wayfinding was interrupted. Please wait."
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        statusLabel.text = "We're back on track!"
    }
}

// Supported destinations (this could be fetched from API instead)
enum Destination {
    case create
    case photobooth
}
