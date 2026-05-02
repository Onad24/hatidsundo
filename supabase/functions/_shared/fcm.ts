import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

/**
 * Sends an FCM push notification to a user by looking up their tokens in the database.
 * Also stores a copy of the notification in the notifications table.
 */
export async function sendFcmNotification(
  supabaseClient: any,
  userId: string,
  title: string,
  body: string,
  data: Record<string, string> = {}
): Promise<{ sent: boolean; sentCount: number; totalTokens: number }> {
  try {
    // Look up user's FCM tokens
    const { data: tokens, error: tokensError } = await supabaseClient
      .from('user_fcm_tokens')
      .select('token')
      .eq('user_id', userId);

    if (tokensError) {
      console.error('Error fetching FCM tokens:', tokensError);
      return { sent: false, sentCount: 0, totalTokens: 0 };
    }

    if (!tokens || tokens.length === 0) {
      console.log(`No FCM tokens found for user ${userId}`);
      // Still insert notification record even if no FCM token
      await _insertNotification(supabaseClient, userId, title, body, data);
      return { sent: false, sentCount: 0, totalTokens: 0 };
    }

    // Get Firebase service account key from secrets
    const firebaseServiceAccountKey = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_KEY');
    
    let sentCount = 0;

    if (firebaseServiceAccountKey) {
      // Send FCM via Firebase HTTP v1 API
      const serviceAccount = JSON.parse(firebaseServiceAccountKey);
      const accessToken = await getFirebaseAccessToken(serviceAccount);

      if (accessToken) {
        for (const { token } of tokens) {
          try {
            const response = await fetch(
              `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`,
              {
                method: 'POST',
                headers: {
                  'Authorization': `Bearer ${accessToken}`,
                  'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                  message: {
                    token: token,
                    notification: {
                      title: title,
                      body: body,
                    },
                    data: {
                      ...data,
                      click_action: 'FLUTTER_NOTIFICATION_CLICK',
                    },
                    android: {
                      priority: 'high',
                      notification: {
                        channel_id: data.type === 'chat_message' 
                          ? 'hatid_sundo_chat' 
                          : data.type === 'new_ride_request'
                          ? 'hatid_sundo_rides'
                          : 'hatid_sundo_channel',
                        sound: 'default',
                      },
                    },
                  },
                }),
              }
            );

            if (response.ok) {
              sentCount++;
            } else {
              const errorBody = await response.text();
              console.error(`FCM send error for token ${token.substring(0, 10)}...: ${errorBody}`);
              
              // Remove invalid tokens
              if (errorBody.includes('UNREGISTERED') || errorBody.includes('INVALID_ARGUMENT')) {
                await supabaseClient
                  .from('user_fcm_tokens')
                  .delete()
                  .eq('token', token);
                console.log('Removed invalid FCM token');
              }
            }
          } catch (e) {
            console.error('FCM send error:', e);
          }
        }
      }
    } else {
      console.log('FIREBASE_SERVICE_ACCOUNT_KEY not set, skipping FCM push. Notification stored in DB.');
    }

    // Always store notification in DB as well
    await _insertNotification(supabaseClient, userId, title, body, data);

    return {
      sent: sentCount > 0,
      sentCount: sentCount,
      totalTokens: tokens.length,
    };
  } catch (error) {
    console.error('Error in sendFcmNotification:', error);
    return { sent: false, sentCount: 0, totalTokens: 0 };
  }
}

/**
 * Insert a notification record into the database
 */
async function _insertNotification(
  supabaseClient: any,
  userId: string,
  title: string,
  body: string,
  data: Record<string, string>
) {
  try {
    await supabaseClient.from('notifications').insert({
      user_id: userId,
      type: data.type || 'general',
      title: title,
      body: body,
      payload: data,
      read: false,
    });
  } catch (e) {
    console.error('Error storing notification:', e);
  }
}

/**
 * Get a Firebase access token using a service account key
 * Uses the Google Auth library approach for Deno
 */
async function getFirebaseAccessToken(serviceAccount: any): Promise<string | null> {
  try {
    const now = Math.floor(Date.now() / 1000);
    const header = { alg: 'RS256', typ: 'JWT' };
    const claims = {
      iss: serviceAccount.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      exp: now + 3600,
      iat: now,
    };

    // Create JWT
    const encodedHeader = base64UrlEncode(JSON.stringify(header));
    const encodedClaims = base64UrlEncode(JSON.stringify(claims));
    const signatureInput = `${encodedHeader}.${encodedClaims}`;

    // Sign with RSA
    const privateKey = serviceAccount.private_key;
    const key = await crypto.subtle.importKey(
      'pkcs8',
      pemToArrayBuffer(privateKey),
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
      false,
      ['sign']
    );

    const signature = await crypto.subtle.sign(
      'RSASSA-PKCS1-v1_5',
      key,
      new TextEncoder().encode(signatureInput)
    );

    const encodedSignature = base64UrlEncode(
      String.fromCharCode(...new Uint8Array(signature))
    );

    const jwt = `${signatureInput}.${encodedSignature}`;

    // Exchange JWT for access token
    const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
    });

    if (!tokenResponse.ok) {
      console.error('Token exchange failed:', await tokenResponse.text());
      return null;
    }

    const tokenData = await tokenResponse.json();
    return tokenData.access_token;
  } catch (e) {
    console.error('Error getting Firebase access token:', e);
    return null;
  }
}

function base64UrlEncode(str: string): string {
  return btoa(str)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\n/g, '');
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}
