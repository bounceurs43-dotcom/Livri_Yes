let cartData = window.cartData || {};
let elements;
let stripe;

function updateOrderSummary() {
    if (!cartData || !cartData.finalTotal) return;

    const formatPrice = (price) => (Math.round(price * 100) / 100).toFixed(2) + '€';

    document.getElementById('cartTotal').textContent = formatPrice(cartData.cartTotal || 0);
    document.getElementById('deliveryFee').textContent = formatPrice(cartData.deliveryFee || 0);
    document.getElementById('finalTotal').textContent = formatPrice(cartData.finalTotal || 0);

    if (cartData.expressFee && cartData.expressFee > 0) {
        document.getElementById('expressFeeContainer').style.display = 'flex';
        document.getElementById('expressFee').textContent = formatPrice(cartData.expressFee);
    }
    if (cartData.tip && cartData.tip > 0) {
        document.getElementById('tipContainer').style.display = 'flex';
        document.getElementById('tipAmount').textContent = formatPrice(cartData.tip);
    }
}

function resultMessage(message, type = 'info') {
    const container = document.querySelector("#result-message");
    container.innerHTML = message;
    container.className = type;
}

function setLoading(isLoading) {
    if (isLoading) {
        document.querySelector("#submit").disabled = true;
        document.querySelector("#spinner").style.display = "inline-block";
        document.querySelector("#button-text").style.display = "none";
    } else {
        document.querySelector("#submit").disabled = false;
        document.querySelector("#spinner").style.display = "none";
        document.querySelector("#button-text").style.display = "inline-block";
    }
}

async function initializeStripe() {
    try {
        updateOrderSummary();
        const clientSecret = cartData.testClientSecret;
        const publishableKey = cartData.testPublishableKey;

        if (!clientSecret || !publishableKey) {
            throw new Error("Clés de paiement introuvables. Veuillez réessayer.");
        }

        // Initialize Stripe.js
        stripe = Stripe(publishableKey);

        const appearance = {
            theme: 'stripe',
            variables: {
                colorPrimary: '#10AA2E',
            },
        };

        elements = stripe.elements({ appearance, clientSecret });

        const paymentElementOptions = {
            layout: "tabs",
            wallets: {
                applePay: 'never',
                googlePay: 'auto'
            }
        };

        const paymentElement = elements.create("payment", paymentElementOptions);
        paymentElement.mount("#payment-element");

        setLoading(false);

    } catch (e) {
        setLoading(false);
        resultMessage(e.message, "error");
    }
}

document.querySelector("#payment-form").addEventListener("submit", handleSubmit);

async function handleSubmit(e) {
    e.preventDefault();
    setLoading(true);

    try {
        const { error, paymentIntent } = await stripe.confirmPayment({
            elements,
            confirmParams: {
                return_url: "https://salimstore.onrender.com/payment-success",
            },
            redirect: 'if_required', // Avoids full page redirect if not required by the bank
        });

        if (error) {
            if (error.type === "card_error" || error.type === "validation_error") {
                resultMessage(error.message, "error");
            } else {
                resultMessage(`Erreur inattendue (${error.type}): ${error.message || "Impossible de vérifier la source d'erreur."}`, "error");
                console.error("Stripe confirmPayment error:", error);
            }
        } else if (paymentIntent && paymentIntent.status === 'succeeded') {
            // Payment succeeded
            resultMessage("Paiement validé avec succès. Création de la commande...", "info");

            // Push PaymentIntent ID back to Flutter so it can create the Firebase order
            setTimeout(() => {
                if (window.StripeSuccess) {
                    window.StripeSuccess.postMessage(paymentIntent.id);
                } else if (window.flutter_inappwebview) {
                    window.flutter_inappwebview.callHandler('orderCreated', { orderId: paymentIntent.id });
                } else {
                    window.location.href = `https://salimstore.onrender.com/payment-success?orderId=${paymentIntent.id}`;
                }
            }, 500);
        } else {
            // Still pending or requires action
            resultMessage("Le paiement nécessite une autre action. Veuillez suivre les instructions de votre banque.", "info");
        }
    } catch (e) {
        resultMessage(`Erreur de traitement: ${e.message}`, "error");
        console.error("Stripe catch error:", e);
    } finally {
        setLoading(false);
    }
}


document.addEventListener('DOMContentLoaded', initializeStripe);

const cancelButton = document.getElementById('cancel-button');
if (cancelButton) {
    cancelButton.addEventListener('click', function () {
        if (window.StripeCancel && window.StripeCancel.postMessage) {
            window.StripeCancel.postMessage('cancel');
        } else {
            window.history.back();
        }
    });
}
