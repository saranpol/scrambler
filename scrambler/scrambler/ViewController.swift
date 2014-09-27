//
//  ViewController.swift
//  scrambler
//
//  Created by saranpol on 9/26/2557 BE.
//  Copyright (c) 2557 saranpol. All rights reserved.
//

//https://github.com/jpwidmer/iOS7-BarcodeScanner

import UIKit
import AVFoundation

class ViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {

    @IBOutlet var mView: UIView!
    
    var _captureSession: AVCaptureSession!
    var _videoDevice: AVCaptureDevice!
    var _videoInput: AVCaptureDeviceInput!
    var _previewLayer: AVCaptureVideoPreviewLayer!
    var _running: Bool!
    var _metadataOutput: AVCaptureMetadataOutput!
    
    var mURL: String!
    
    
    override func prefersStatusBarHidden() -> Bool {
        return true;
    }
    
    func frontCamera() -> AVCaptureDevice? {
        var devices = AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo)
        for device in devices {
            if device.position == AVCaptureDevicePosition.Front {
                return device as? AVCaptureDevice
            }
        }
        return AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeVideo)
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        _running = false
        
//        if (_captureSession) return;

        _videoDevice = frontCamera()
        if _videoDevice == nil {
            println("No video camera on this device!")
            return;
        }

        _captureSession = AVCaptureSession()
        
        
        _videoInput = AVCaptureDeviceInput.deviceInputWithDevice(_videoDevice, error:nil) as AVCaptureDeviceInput

        
        if(_captureSession.canAddInput(_videoInput)){
            _captureSession.addInput(_videoInput)
        }

        
        _previewLayer = AVCaptureVideoPreviewLayer.layerWithSession(_captureSession) as AVCaptureVideoPreviewLayer
        _previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        
        
        _metadataOutput = AVCaptureMetadataOutput()
        var metadataQueue:dispatch_queue_t = dispatch_queue_create("com.hlpth.test.scrambler.metadata", nil)
        _metadataOutput.setMetadataObjectsDelegate(self, queue: metadataQueue)
        
        if _captureSession.canAddOutput(_metadataOutput) {
            _captureSession.addOutput(_metadataOutput)
        }
        
        
        
        
        _previewLayer.frame = mView.bounds
        mView.layer.addSublayer(_previewLayer)
        
//        self.foundBarcodes = [[NSMutableArray alloc] init];
        
//        // listen for going into the background and stop the session
//        [[NSNotificationCenter defaultCenter]
//        addObserver:self
//        selector:@selector(applicationWillEnterForeground:)
//        name:UIApplicationWillEnterForegroundNotification
//        object:nil];
//        [[NSNotificationCenter defaultCenter]
//        addObserver:self
//        selector:@selector(applicationDidEnterBackground:)
//        name:UIApplicationDidEnterBackgroundNotification
//        object:nil];
        
//        allowedBarcodeTypes = [NSMutableArray new];
//        [self.allowedBarcodeTypes addObject:@"org.iso.QRCode"];
//        [self.allowedBarcodeTypes addObject:@"org.iso.PDF417"];
//        [self.allowedBarcodeTypes addObject:@"org.gs1.UPC-E"];
//        [self.allowedBarcodeTypes addObject:@"org.iso.Aztec"];
//        [self.allowedBarcodeTypes addObject:@"org.iso.Code39"];
//        [self.allowedBarcodeTypes addObject:@"org.iso.Code39Mod43"];
//        [self.allowedBarcodeTypes addObject:@"org.gs1.EAN-13"];
//        [self.allowedBarcodeTypes addObject:@"org.gs1.EAN-8"];
//        [self.allowedBarcodeTypes addObject:@"com.intermec.Code93"];
//        [self.allowedBarcodeTypes addObject:@"org.iso.Code128"];
        
        
        
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        startRunning()
    }
    
    override func viewDidDisappear(animated: Bool) {
        super.viewDidDisappear(animated)
        stopRunning()
    }
    
    func startRunning() {
        if (_running==true ||  _videoInput==nil){
            return
        }
        _captureSession.startRunning()
        _metadataOutput.metadataObjectTypes = _metadataOutput.availableMetadataObjectTypes;
        _running = true
    }
    
    func stopRunning() {
        if _running==false {
            return
        }
        _captureSession.stopRunning()
        _running = false
    }

    
    func loadNextView() {
        self.performSegueWithIdentifier("GotoViewResult", sender: nil)
    }
    
    
    func captureOutput(captureOutput: AVCaptureOutput!, didOutputMetadataObjects metadataObjects: [AnyObject]!, fromConnection connection: AVCaptureConnection!){
        

        
        var a: NSArray = NSArray(array: metadataObjects)
        a.enumerateObjectsUsingBlock({obj, idx, stop in
            if((obj as? AVMetadataMachineReadableCodeObject) != nil){
                let code:AVMetadataMachineReadableCodeObject = self._previewLayer.transformedMetadataObjectForMetadataObject(obj as AVMetadataObject) as AVMetadataMachineReadableCodeObject
                if(code.type == "org.iso.QRCode"){
                    println(code.stringValue)
                    self.stopRunning()
                    self.mURL = code.stringValue
                    dispatch_after(1, dispatch_get_main_queue(), {
                        self.loadNextView()
                    })
                    return
                }
            }
        })

        
    }
    
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        let v:ViewResult = segue.destinationViewController as ViewResult
        v.mURL = mURL
    }
    
    
}

