const msalConfig = {
    auth: {
      clientId: "dbe20fc6-2974-448c-bf40-129d8be80e2f",
      authority: "https://login.microsoftonline.com/104742fb-6225-439f-9540-60da5f0317dc",
      //redirectUri: "http://localhost:3000",
      redirectUri: "https://wonderful-pebble-0f9006303.3.azurestaticapps.net",
      //redirectUri: "https://espc2025.elven.no"
    },
    cache: {
      cacheLocation: "sessionStorage", // This configures where your cache will be stored
      storeAuthStateInCookie: false, // Set this to "true" if you are having issues on IE11 or Edge
    }
  };

  // Add here scopes for id token to be used at MS Identity Platform endpoints.
  const loginRequest = {
    scopes: ["openid", "profile"]
  };
