// // Copyright (c) 2023, WSO2 LLC. (http://www.wso2.com). All Rights Reserved.

// This software is the property of WSO2 LLC. and its suppliers, if any.
// Dissemination of any information or reproduction of any material contained
// herein is strictly forbidden, unless permitted by WSO2 in accordance with
// the WSO2 Software License available at: https://wso2.com/licenses/eula/3.2
// For specific language governing the permissions and limitations under
// this license, please see the license as well as any agreement you’ve
// entered into with WSO2 governing the purchase of this software and any
// associated services.


import ballerina/http;
import ballerina/log;

configurable string epic_connect_api = ?;
configurable string cerner_connect_api = ?;

// final string READ = sourceSystem.endsWith("/") ? "read/" : "/read/";
// final string SEARCH = sourceSystem.endsWith("/") ? "search" : "/search";
// final string CREATE = sourceSystem.endsWith("/") ? "create" : "/create";

final http:Client epicApi = check new (epic_connect_api);
final http:Client cernerApi = check new (cerner_connect_api);

service http:Service / on new http:Listener(9090) {

    // Get resource by ID
    isolated resource function get patient/[string id](string emr) returns http:Response|http:ClientError {
        log:printInfo("Get patient by ID: " + id + " from " + emr);
        http:Response|http:ClientError res;
        if (emr === "epic") {
            res = epicApi->get("Patient/"+id);
        } else if (emr === "cerner") {
            res = cernerApi->get("Patient/"+id);
        } else {
            res = handleError("Invalid EMR", 500);
        }

        return res;
    }

}

isolated function handleError(string msg, int statusCode = http:STATUS_INTERNAL_SERVER_ERROR) returns http:Response {
    http:Response finalResponse = new ();
    finalResponse.setPayload(getOperationOutcome(msg));
    finalResponse.statusCode = statusCode;
    return finalResponse;
}

isolated function getOperationOutcome(string detail) returns json {

    return {
        "resourceType": "OperationOutcome",
        "issue": [
            {
                "severity": "error",
                "code": "error",
                "details": {
                    "text": detail
                }
            }
        ]
    };
}
