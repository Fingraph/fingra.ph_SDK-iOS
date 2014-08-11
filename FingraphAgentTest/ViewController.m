/*******************************************************************************
 * Copyright 2014 tgrape Inc.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *  http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *******************************************************************************/
#import "ViewController.h"
#import "FingraphAgent.h"
@interface ViewController (){
    UITapGestureRecognizer *tapGesRoc;
}
@property (weak, nonatomic) IBOutlet UITextField *count;
@property (weak, nonatomic) IBOutlet UITextField *totalCharge;
@property (weak, nonatomic) IBOutlet UISegmentedControl *unitSegment;
@property (weak, nonatomic) IBOutlet UILabel *addressLabel;

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.

    tapGesRoc = [[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(hideKeyboard)];
    [self.view addGestureRecognizer:tapGesRoc];
    [self.addressLabel setText:FINGRAPHAGENT_SERVER_URL];
}

- (void)hideKeyboard{
    [_count resignFirstResponder];
    [_totalCharge resignFirstResponder];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)pageview:(id)sender {
    [FingraphAgent onPageView];
}

- (IBAction)event:(id)sender {
    [FingraphAgent onEvent:@"evt123456"];
}
@end
