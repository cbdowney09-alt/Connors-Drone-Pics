package com.knoxcanvas.app

import android.app.Activity
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.NoCredentialException
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.google.android.libraries.identity.googleid.GoogleIdTokenParsingException

/**
 * Google sign-in for the Android app.
 *
 * Google refuses to show its login page inside a WebView ("disallowed_useragent"), so the page's
 * popup/redirect flow can't work here. Instead Android's own account picker (Credential Manager)
 * returns a Google ID token, and the page signs in to Firebase with `signInWithCredential`.
 *
 * Setup: register the Android app in Firebase with its SHA-1 and paste the Web client ID into
 * `AppConfig.GOOGLE_WEB_CLIENT_ID` (see android/README.md).
 */
object GoogleSignIn {
    class SignInException(message: String) : Exception(message)

    private var running = false

    /** Returns a Google ID token, or null if the user backed out. Throws with a readable message otherwise. */
    suspend fun signIn(activity: Activity): String? {
        val clientId = AppConfig.GOOGLE_WEB_CLIENT_ID
        if (!clientId.endsWith(".apps.googleusercontent.com") || clientId.startsWith("PASTE")) {
            throw SignInException("Google sign-in isn't set up in the Android app yet. Use email and password for now.")
        }
        if (running) return null   // already showing (the page's popup and redirect can both trigger it)
        running = true
        try {
            val request = GetCredentialRequest.Builder()
                .addCredentialOption(GetSignInWithGoogleOption.Builder(clientId).build())
                .build()
            val credential = CredentialManager.create(activity).getCredential(activity, request).credential
            if (credential is CustomCredential && credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) {
                return GoogleIdTokenCredential.createFrom(credential.data).idToken
            }
            throw SignInException("Google didn't return a sign-in token.")
        } catch (e: GetCredentialCancellationException) {
            return null
        } catch (e: NoCredentialException) {
            throw SignInException("There's no Google account on this phone. Add one in Settings → Accounts, or use email and password.")
        } catch (e: GetCredentialException) {
            throw SignInException(e.message ?: "Google sign-in failed. Try again.")
        } catch (e: GoogleIdTokenParsingException) {
            throw SignInException("Google sign-in failed. Try again.")
        } finally {
            running = false
        }
    }
}
