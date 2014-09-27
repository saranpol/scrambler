//
//  ViewFinal.swift
//  scrambler
//
//  Created by saranpol on 9/26/2557 BE.
//  Copyright (c) 2557 saranpol. All rights reserved.
//

import UIKit


class ViewFinal: UIViewController {
    var mURL: String!
    @IBOutlet var mImageView: UIImageView!
    @IBOutlet var mLoading: UIActivityIndicatorView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        mImageView.hidden = true
        updateWin()
    }
    
    @IBAction func clickBack(AnyObject) {
        navigationController?.popToRootViewControllerAnimated(true)
    }

    override func prefersStatusBarHidden() -> Bool {
        return true;
    }
    
    
    func updateWin() {
        request(.POST, "http://www.scramblerthailand.com/api/update", parameters: ["url":mURL])
//            .responseJSON { (request, response, JSON, error) in
            .responseString{ (request, response, s, error) in
                if error == nil {
                    self.mImageView.hidden = false
                    println(s)
                    
                }else{
                    let alert = UIAlertView()
                    alert.title = "Error"
                    alert.message = "Please try again"
                    alert.addButtonWithTitle("OK")
                    alert.show()
                }
                
                self.mLoading.hidden = true
        }
    }
    
}