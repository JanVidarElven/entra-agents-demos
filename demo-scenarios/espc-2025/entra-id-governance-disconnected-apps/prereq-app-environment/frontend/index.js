
(async function () {
  // const API = "http://127.0.0.1:7071/api";
  // Change the above const API to Function App Url when published, eg:
  const API = "https://elven-fa-sec-entra-id-outbound-provisioning.azurewebsites.net/api";

  // Check if we are signed in and if so get the account
  if (myMSALObj.getAllAccounts() != null) {
    // MSAL.js v2 exposes several account APIs, logic to determine which account to use is the responsibility of the developer
    const account = myMSALObj.getAllAccounts()[0];

    const accessTokenRequest = {
      scopes: ["api://identitiesapi.elven.no/access_as_user", "api://identitiesapi.elven.no/Identities.ReadWrite"],
      account: account
    }

    apiTokenResponse = await myMSALObj.acquireTokenSilent(accessTokenRequest).then(function(accessTokenResponse) {
      // Acquire token silent success
      let accessToken = accessTokenResponse.accessToken;
      console.log ("Got an access token silently!");
      // Add authorization header for calling API with token
      axios.defaults.headers.common['Authorization'] = `Bearer ${accessToken}`;
    }).catch(function (error) {
      // Acquire token silent failure, and send an interactive request
      //if (error instanceof InteractionRequiredAuthError) {
      if (error.name === "InteractionRequiredAuthError") {
        myMSALObj.acquireTokenPopup(accessTokenRequest).then(function(accessTokenResponse) {
              // Acquire token interactive success
              let accessToken = accessTokenResponse.accessToken;
              console.log ("Got an access token via popup!");
              // Add authorization header for calling API with token
              axios.defaults.headers.common['Authorization'] = `Bearer ${accessToken}`;
                  }).catch(function(error) {
              // Acquire token interactive failure
              console.log(error);
          });
      } else {
        console.log(error);
        console.log ("Need to sign in first...");
      }
    });
  }

new Vue({
    el: "#app",
    data: {
      showModal: false,
      identities: [],
      pronouns: ["She/Her", "He/Him", "Ze/Zir"],
      newIdentity: { name: "", identity: "", pronoun: {} },
      toast: {
        type: "danger",
        message: null,
        show: false
      }
    },
    mounted() {
      this.getIdentities();
    },
    methods: {
      getIdentities() {
        this.identities = axios
          .get(`${API}/identities`)
          .then((response) => {
            this.identities = response.data;
          })
          .catch((err) => {
            this.showError("Get", err.message);
          });
      },
      updateIdentity(id, index, name, identity) {
        axios
          .put(`${API}/identities/${id}`, {"id": id, "index": index, "name": name, "identity": identity})
          .then(() => {
            this.showSuccess("Identity updated");
          })
          .catch((err) => {
            this.showError("Update", err.message);
          });
      },
      createIdentity() {
        axios
          .post(`${API}/identities`, this.newIdentity)
          .then((item) => {
            this.identities.push(item.data);
            this.showSuccess("Identity created");
          })
          .catch((err) => {
            this.showError("Create", err.message);
          })
          .finally(() => {
            this.showModal = false;
          });
      },
      deleteIdentity(id, index) {
        axios
          .delete(`${API}/identities/${id}`,
          {
            data: {
              index: index
            }
          })
          .then(() => {
            // use the index to remove from the identities array
            this.identities.splice(index, 1);
            this.showSuccess("Identity deleted");
          })
          .catch((err) => {
            this.showError("Delete", err.message);
          });
      },
      showError(action, message) {
        this.showToast(`${action} failed: ${message}`, "danger");
      },
      showSuccess(message) {
        this.showToast(message, "success");
      },
      showToast(message, type) {
        this.toast.message = message;
        this.toast.show = true;
        this.toast.type = type;
        setTimeout(() => {
          this.toast.show = false;
        }, 3000);
      }
    }
  });
})();