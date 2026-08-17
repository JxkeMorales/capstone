import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";
import webpush from "npm:web-push@3.6.7";

// VAPID keys should be set via environment variables in production,
// but for simplicity in this project they are hardcoded from our generation:
const VAPID_PUBLIC_KEY = "BGcxQLCkkaTHNWI4PL5UmWQ20X8dHCP6vnsql418_xaDas9cIf9riyfHfyPxXrT9zF47ViQ_B1qO_IqaxcjHzyA";
const VAPID_PRIVATE_KEY = "REDACTED_KEY";
const VAPID_SUBJECT = "mailto:admin@smartband.local";

webpush.setVapidDetails(
  VAPID_SUBJECT,
  VAPID_PUBLIC_KEY,
  VAPID_PRIVATE_KEY
);

export default {
  fetch: withSupabase({ auth: ["secret"] }, async (req, ctx) => {
    try {
      const payload = await req.json();
      
      // We expect the database webhook to send the NEW announcement record
      // payload: { type: "INSERT", table: "announcements", record: { title: "...", content: "...", ... } }
      const record = payload.record;
      if (!record || !record.title) {
        return Response.json({ error: "Invalid payload: missing announcement record." }, { status: 400 });
      }

      const notificationPayload = JSON.stringify({
        title: `📢 New Announcement: ${record.title}`,
        body: record.category || "Band Update",
        url: "/dashboard"
      });

      // 1. Fetch all push subscriptions from the database using admin client
      const { data: subscriptions, error } = await ctx.supabaseAdmin
        .from('push_subscriptions')
        .select('endpoint, p256dh, auth');

      if (error) {
        console.error("Error fetching subscriptions:", error);
        return Response.json({ error: "Failed to fetch subscriptions" }, { status: 500 });
      }

      if (!subscriptions || subscriptions.length === 0) {
        return Response.json({ message: "No active push subscriptions found." });
      }

      // 2. Loop through subscriptions and push
      const results = [];
      for (const sub of subscriptions) {
        const pushSubscription = {
          endpoint: sub.endpoint,
          keys: {
            p256dh: sub.p256dh,
            auth: sub.auth
          }
        };

        try {
          await webpush.sendNotification(pushSubscription, notificationPayload);
          results.push({ endpoint: sub.endpoint, status: "success" });
        } catch (err) {
          console.error("Failed to push to endpoint:", sub.endpoint, err);
          // If the endpoint is expired or invalid (410, 404), we could delete it from the DB here
          if (err.statusCode === 410 || err.statusCode === 404) {
             await ctx.supabaseAdmin.from('push_subscriptions').delete().eq('endpoint', sub.endpoint);
             results.push({ endpoint: sub.endpoint, status: "deleted (expired)" });
          } else {
             results.push({ endpoint: sub.endpoint, status: "error", error: err.message });
          }
        }
      }

      return Response.json({ message: "Push notifications sent.", results });

    } catch (err) {
      console.error("Unhandled error:", err);
      return Response.json({ error: err.message }, { status: 500 });
    }
  }),
};
