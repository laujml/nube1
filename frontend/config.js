// Configuracion de entorno del frontend. Edita estos valores con los reales
// despues de correr "terraform apply" (salen de terraform output):
//   API_BASE_URL <- terraform output api_url   (sin barra final)
//   API_KEY      <- terraform output api_key_value  (opcional: ningun
//                    metodo del API tiene api_key_required=true todavia,
//                    asi que hoy no se exige, pero se manda si esta seteada
//                    por si se activa mas adelante)
window.CLOUDSHOP_CONFIG = {
  API_BASE_URL: "https://o1azy3dvg7.execute-api.us-east-1.amazonaws.com/dev",
  API_KEY: "",
};
