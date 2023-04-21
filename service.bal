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
    string? addressText;
};

service http:Service / on new http:Listener(9090) {

    // Get resource by ID
    isolated resource function get patient/[string id](string emr, boolean transform) returns http:Response|http:ClientError|error {
        log:printInfo("Get patient by ID: " + id + " from " + emr);
        http:Response|http:ClientError res;
        if (emr === "epic") {
            res = epicApi->get("/fhir/r4/Patient/" + id);
        } else if (emr === "cerner") {
            res = cernerApi->get("/fhir/r4/Patient/" + id);
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

    // Create a resource
    isolated resource function post patient(@http:Payload CustomPatient patient, string emr) returns http:Response|http:ClientError|error {
        log:printInfo("Create patient on " + emr);
        http:Response|http:ClientError res;

        r4:Patient fhirPatient = transformCustomPatientToFhirPatient(patient);
        log:printInfo(fhirPatient.toJson().toString());
        if (emr === "epic") {
            res = epicApi->post("/fhir/r4/Patient", fhirPatient);
        } else if (emr === "cerner") {
            res = cernerApi->post("/fhir/r4/Patient", fhirPatient);
        } else {
            res = handleError("Invalid [EMR] " + emr, 404);
        }

        if (res is http:ClientError) {
            log:printError("Error occurred while invoking the EMR", res);
            return handleError("Error occurred while invoking the EMR. Error: " + res.message(), 500);
        }
        return res;
    }

}

isolated function transformFhirPatientToCustomPatient(r4:Patient patient) returns CustomPatient => {
    resourceType: patient.resourceType,
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

    gender: patient.gender,
    addressText: getAddressText(patient.address)

};

isolated function getAddressText(r4:Address[]? addresses) returns string? {
    if addresses is r4:Address[] {
        return addresses[0].text;
    }
    return ();
}

isolated function transformCustomPatientToFhirPatient(CustomPatient patient) returns r4:Patient => {
    resourceType: r4:RESOURCE_NAME_PATIENT,
    identifier: [
        {use: r4:usual, system: "urn:oid:2.16.840.1.113883.4.1", value: "000-00-0000"}
    ],
    active: patient.active,
    name: from var nameItem in patient.name
        select {
            use: <r4:HumanNameUse>nameItem.use,
            family: nameItem.family,
            given: nameItem.given
        },
    gender: <r4:PatientGender>patient.gender,
    birthDate: patient.birthDate,
    address: extracted(patient)
};

isolated function extracted(CustomPatient patient) returns r4:Address[]? {
    return [{
        use: "home",
        line: getAddressLine(patient.addressText),
        city: "Verona",
        state: "WI",
        postalCode: "53593",
        country: "USA",
        text: patient.addressText
        }];
}

isolated function getAddressLine(string? addressText) returns string[]? {
    if addressText is string {
        return [ addressText ];
    }
    return [];
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
