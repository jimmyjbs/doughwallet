//
//  BRPaymentRequest.m
//  BreadWallet
//
//  Created by Aaron Voisine on 5/9/13.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

#import "BRPaymentRequest.h"
#import "BRPaymentProtocol.h"
#import "NSString+Base58.h"
#import "NSMutableData+Bitcoin.h"

// BIP21 bitcoin URI object https://github.com/bitcoin/bips/blob/master/bip-0021.mediawiki
@implementation BRPaymentRequest

+ (instancetype)requestWithString:(NSString *)string
{
    return [[self alloc] initWithString:string];
}

+ (instancetype)requestWithData:(NSData *)data
{
    return [[self alloc] initWithData:data];
}

+ (instancetype)requestWithURL:(NSURL *)url
{
    return [[self alloc] initWithURL:url];
}

- (instancetype)initWithString:(NSString *)string
{
    if (! (self = [self init])) return nil;
    
    self.string = string;
    return self;
}

- (instancetype)initWithData:(NSData *)data
{
    return [self initWithString:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
}

- (instancetype)initWithURL:(NSURL *)url
{
    return [self initWithString:url.absoluteString];
}

- (void)setString:(NSString *)string
{
    self.paymentAddress = nil;
    self.label = nil;
    self.message = nil;
    self.amount = 0;
    self.r = nil;

    if (! string.length) return;

    NSString *s = [[string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
                   stringByReplacingOccurrencesOfString:@" " withString:@"%20"];
    NSURL *url = [NSURL URLWithString:s];
    
    if (! url || ! url.scheme) {
        url = [NSURL URLWithString:[NSString stringWithFormat:@"dogecoin://%@", s]];
    }
    else if (! url.host && url.resourceSpecifier) {
        url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@", url.scheme, url.resourceSpecifier]];
    }
    
    self.paymentAddress = url.host;
    
    //TODO: correctly handle unkown but required url arguments (by reporting the request invalid)
    for (NSString *arg in [url.query componentsSeparatedByString:@"&"]) {
        NSArray *pair = [arg componentsSeparatedByString:@"="];
        NSString *value = (pair.count > 1) ? [arg substringFromIndex:[pair[0] length] + 1] : nil;
        
        if ([pair[0] isEqual:@"amount"]) {
            self.amount = ([value doubleValue] + DBL_EPSILON)*SATOSHIS;
        }
        else if ([pair[0] isEqual:@"label"]) {
            self.label = [[value stringByReplacingOccurrencesOfString:@"+" withString:@"%20"]
                          stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        }
        else if ([pair[0] isEqual:@"message"]) {
            self.message = [[value stringByReplacingOccurrencesOfString:@"+" withString:@"%20"]
                            stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        }
        else if ([pair[0] isEqual:@"r"]) {
            self.r = [[value stringByReplacingOccurrencesOfString:@"+" withString:@"%20"]
                      stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        }
    }
}

- (NSString *)string
{
    if (! self.paymentAddress) return nil;

    NSMutableString *s = [NSMutableString stringWithFormat:@"dogecoin:%@", self.paymentAddress];
    NSMutableArray *q = [NSMutableArray array];
    
    if (self.amount > 0) {
        [q addObject:[NSString stringWithFormat:@"amount=%.16g", (double)self.amount/SATOSHIS]];
    }

    if (self.label.length > 0) {
        [q addObject:[NSString stringWithFormat:@"label=%@",
         CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)self.label, NULL, CFSTR("&="),
                                                                   kCFStringEncodingUTF8))]];
    }
    
    if (self.message.length > 0) {
        [q addObject:[NSString stringWithFormat:@"message=%@",
         CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)self.message, NULL, CFSTR("&="),
                                                                   kCFStringEncodingUTF8))]];
    }

    if (self.r.length > 0) {
        [q addObject:[NSString stringWithFormat:@"r=%@",
         CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)self.r, NULL, CFSTR("&="),
                                                                   kCFStringEncodingUTF8))]];
    }
    
    if (q.count > 0) {
        [s appendString:@"?"];
        [s appendString:[q componentsJoinedByString:@"&"]];
    }
    
    return s;
}

- (void)setData:(NSData *)data
{
    self.string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (NSData *)data
{
    return [self.string dataUsingEncoding:NSUTF8StringEncoding];
}

- (void)setUrl:(NSURL *)url
{
    self.string = url.absoluteString;
}

- (NSURL *)url
{
    return [NSURL URLWithString:self.string];
}

- (BOOL)isValid
{
    if (! [self.paymentAddress isValidBitcoinAddress] && (! self.r || ! [NSURL URLWithString:self.r])) return NO;

    return YES;
}

// reciever converted to BIP70 request object
- (BRPaymentProtocolRequest *)protocolRequest
{
    static NSString *network = @"main";
#if BITCOIN_TESTNET
    network = @"test";
#endif
    NSData *name = [self.label dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *script = [NSMutableData data];
    
    [script appendScriptPubKeyForAddress:self.paymentAddress];
    
    BRPaymentProtocolDetails *details =
        [[BRPaymentProtocolDetails alloc] initWithNetwork:network outputAmounts:@[@(self.amount)]
         outputScripts:@[script] time:[[NSDate date] timeIntervalSinceReferenceDate]
         expires:UINT32_MAX - NSTimeIntervalSince1970 memo:self.message paymentURL:nil merchantData:nil];
    BRPaymentProtocolRequest *request =
        [[BRPaymentProtocolRequest alloc] initWithVersion:1 pkiType:@"none" certs:(name ? @[name] : nil) details:details
         signature:nil];
    
    return request;
}

// fetches the request over HTTP and calls completion block
+ (void)fetch:(NSString *)url timeout:(NSTimeInterval)timeout
completion:(void (^)(BRPaymentProtocolRequest *req, NSError *error))completion
{
    if (! completion) return;

    NSURL *u = [NSURL URLWithString:url];

    if (! u) {
        completion(nil, [NSError errorWithDomain:@"DoughWallet" code:417 userInfo:@{NSLocalizedDescriptionKey:
                         NSLocalizedString(@"bad payment request URL", nil)}]);
        return;
    }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:u
                                cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:timeout];

    [req addValue:@"application/vnd.doge.payment.request" forHTTPHeaderField:@"Accept"];

    [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue currentQueue]
    completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        if (! [response.MIMEType.lowercaseString isEqual:@"application/vnd.doge.payment.request"] || data.length > 50000){
            completion(nil, [NSError errorWithDomain:@"DoughWallet" code:417 userInfo:@{NSLocalizedDescriptionKey:
                             [NSString stringWithFormat:NSLocalizedString(@"unexpected response from %@", nil), u.host]
                            }]);
            return;
        }

        BRPaymentProtocolRequest *req = [BRPaymentProtocolRequest requestWithData:data];
        NSString *network = @"main";

#ifdef BITCOIN_TESTNET
        network = @"test";
#endif

        if (! req) {
            completion(nil, [NSError errorWithDomain:@"DoughWallet" code:417 userInfo:@{NSLocalizedDescriptionKey:
                             [NSString stringWithFormat:NSLocalizedString(@"unexpected response from %@", nil), u.host]
                            }]);
            return;
        }

        if (! [req.details.network isEqual:network]) {
            completion(nil, [NSError errorWithDomain:@"DoughWallet" code:417 userInfo:@{NSLocalizedDescriptionKey:
                             [NSString stringWithFormat:NSLocalizedString(@"requested network \"%@\" instead of \"%@\"",
                                                                          nil), req.details.network, network]}]);
            return;
        }

        completion(req, nil);
    }];
}

+ (void)postPayment:(BRPaymentProtocolPayment *)payment to:(NSString *)paymentURL timeout:(NSTimeInterval)timeout
completion:(void (^)(BRPaymentProtocolACK *ack, NSError *error))completion
{
    NSURL *u = [NSURL URLWithString:paymentURL];

    if (! u) {
        completion(nil, [NSError errorWithDomain:@"Breadwallet" code:417
                         userInfo:@{NSLocalizedDescriptionKey:NSLocalizedString(@"bad payment URL", nil)}]);
        return;
    }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:u
                                cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:timeout];

    [req addValue:@"application/vnd.doge.payment.payment" forHTTPHeaderField:@"Content-Type"];
    [req addValue:@"application/vnd.doge.payment.ack" forHTTPHeaderField:@"Accept"];
    [req setHTTPMethod:@"POST"];
    [req setHTTPBody:payment.data];

    [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue currentQueue]
    completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        if (connectionError) {
            completion(nil, connectionError);
            return;
        }

        if (! [response.MIMEType.lowercaseString isEqual:@"application/vnd.doge.payment.ack"] || data.length > 50000) {
            completion(nil, [NSError errorWithDomain:@"DoughWallet" code:417 userInfo:@{NSLocalizedDescriptionKey:
                             [NSString stringWithFormat:NSLocalizedString(@"unexpected response from %@", nil), u.host]
                            }]);
            return;
        }

        BRPaymentProtocolACK *ack = [BRPaymentProtocolACK ackWithData:data];
        
        if (! ack) {
            completion(nil, [NSError errorWithDomain:@"DoughWallet" code:417 userInfo:@{NSLocalizedDescriptionKey:
                             [NSString stringWithFormat:NSLocalizedString(@"unexpected response from %@", nil), u.host]
                            }]);
            return;
        }
        
        completion(ack, nil);
     }];
}

@end
