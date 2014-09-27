//
//  ViewResult.swift
//  scrambler
//
//  Created by saranpol on 9/26/2557 BE.
//  Copyright (c) 2557 saranpol. All rights reserved.
//

import UIKit


class ViewResult: UIViewController {
    var mURL: String!
    @IBOutlet var mView: UIView!
    @IBOutlet var mLoading: UIActivityIndicatorView!
    @IBOutlet var mImageProfile: UIImageView!
    @IBOutlet var mLabelName: UILabel!
    @IBOutlet var mLabelText: UILabel!
    @IBOutlet var mButtonHome: UIButton!
    @IBOutlet var mButtonConfirm: UIButton!
    
    @IBAction func clickBack(AnyObject) {
        navigationController?.popViewControllerAnimated(true)
    }

    override func prefersStatusBarHidden() -> Bool {
        return true;
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        mView.hidden = true
        mLoading.hidden = false
        
        mImageProfile.layer.cornerRadius = mImageProfile.frame.size.width / 2;
        mImageProfile.layer.masksToBounds = true;
        
        checkWin()
    }
    
    func checkWin() {
        request(.POST, "http://www.scramblerthailand.com/api/check", parameters: ["url":mURL])
            .responseJSON { (request, response, JSON, error) in
                if error == nil {
                    self.mView.hidden = false
                    println(JSON)

                    let profile_image: AnyObject? = JSON?.objectForKey("profile_image")
                    let username: AnyObject? = JSON?.objectForKey("username")
                    let status: AnyObject? = JSON?.objectForKey("status")
                    
                    self.mImageProfile.sd_setImageWithURL((NSURL(string: profile_image as String)))
                    let up = username as String
                    self.mLabelName.text = up.uppercaseString
                    
                    
                    
                    if((status as? String) == "0"){
                        self.mLabelText.text = "ฟรี! รับ WELCOME DRINK 1 สิทธิ์"
                        self.mButtonHome.hidden = true;
                        self.mButtonConfirm.hidden = false;
                    }else if((status as? String) == "1"){
                        self.mLabelText.text = "ขอบคุณที่มาร่วมงาน พบกิจกรรมในงานได้เลย"
                        self.mButtonHome.hidden = false;
                        self.mButtonConfirm.hidden = true;
                    }else if((status as? String) == nil){
                        self.mLabelText.text = "ขอบคุณที่มาร่วมงาน พบกิจกรรมในงานได้เลย"
                        self.mButtonHome.hidden = false;
                        self.mButtonConfirm.hidden = true;
                    }
                    

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
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        let v:ViewFinal = segue.destinationViewController as ViewFinal
        v.mURL = mURL
    }
    

}