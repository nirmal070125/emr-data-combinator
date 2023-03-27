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
import wso2healthcare/healthcare.fhir.r4;
import wso2healthcare/healthcare.fhir.r4.parser;

// configurations 
// assumption - all the EMR APIs will be subscribed to a single OAuth application
configurable string epic_connect_api_url = ?;
configurable string cerner_connect_api_url = ?;
configurable string app_clientid = ?;
configurable string app_clientsecret = ?;
configurable string app_tokenurl = ?;

// OAuth2 client configuration
http:ClientAuthConfig authConfig = {
        tokenUrl: app_tokenurl,
        clientId: app_clientid,
        clientSecret: app_clientsecret,
        scopes: [],
        clientConfig: {
        }
    };

// Cerner API client
final http:Client cernerApi = check new (cerner_connect_api_url, auth = authConfig);
// Epic API client
final http:Client epicApi = check new (epic_connect_api_url, auth = authConfig);

// Custom Patient record
type CustomPatient record {
    string resourceType;
    string? id;
    boolean? active;
    record {
        string? use;
        string? family;
        string[]? given;
    }[] name;
    record {
        string? use;
        string? system?;
        string? value?;
        int? rank?;
    }[] telecom;
    string? gender;
    string? birthDate;
};

service http:Service / on new http:Listener(9090) {

    // Get resource by ID
    isolated resource function get patient/[string id](string emr, boolean transform) returns http:Response|http:ClientError|error {
        log:printInfo("Get patient by ID: " + id + " from " + emr);
        http:Response|http:ClientError res;
        if (emr === "epic") {
            res = epicApi->get("/Patient/" + id);
        } else if (emr === "cerner") {
            res = cernerApi->get("/Patient/" + id);
        } else {
            res = handleError("Invalid [EMR] " + emr, 404);
        }
        if (res is http:ClientError) {
            log:printError("Error occurred while invoking the EMR", res);
            return handleError("Error occurred while invoking the EMR. Error: " + res.message(), 500);
        } else if (transform) {
            r4:Patient patient = check parser:parse(check res.getJsonPayload(), r4:Patient).ensureType();
            CustomPatient transformFhirPatientToCustomPatientResult = transformFhirPatientToCustomPatient(patient);
            res.setJsonPayload(transformFhirPatientToCustomPatientResult.toJson());
            log:printInfo("Response transformed.");
        }
        log:printInfo("Response received");
        return res;
    }

}

isolated function transformFhirPatientToCustomPatient(r4:Patient patient) returns CustomPatient => {
    resourceType: patient.resourceType,
    id: patient.id,
    active: patient.active,
    name: let r4:HumanName[]? humanName = patient.name
        in humanName is r4:HumanName[] ? from var nameItem in humanName
            select {
                use: nameItem.use,
                family: nameItem.family,
                given: nameItem.given
            } : ([]),
    telecom: let r4:ContactPoint[]? contactPoint = patient.telecom
        in contactPoint is r4:ContactPoint[] ? from var telecomItem in contactPoint
            select {
                use: telecomItem.use,
                system: telecomItem.system,
                value: telecomItem.value,
                rank: telecomItem.rank
            } : ([]),
    birthDate: patient.birthDate,
    gender: patient.gender

};

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
