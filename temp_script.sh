SECRET=$(grep '^INSTANTLY_WEBHOOK_SECRET=' /home/joe/repos/lead_engine/closet-dashboard/.env.local | cut -d= -f2-)

curl -sS -o /dev/null -w "%{http_code}\n" -X POST \
  https://www.ditchtheform.com/api/webhooks/instantly \
  -H "Content-Type: application/json" \
  -d '{"lead_email":"test@example.com","event_type":"Unsubscribed"}'
# expect 401

curl -sS -w "\n%{http_code}\n" -X POST \
  https://www.ditchtheform.com/api/webhooks/instantly \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $SECRET" \
  -d '{"lead_email":"test-unsub@example.com","event_type":"Unsubscribed"}'
# expect {"ok":true} and 200