
(async function () {
  const API = "http://127.0.0.1:7071/api";

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