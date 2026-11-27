"""Fitur integrasi UNIQLO+: migrasi aman, API member, poin/level, ulasan, order ops."""
import json, math, sqlite3, time, hashlib
from urllib.parse import parse_qs

broadcast_admin_event = None

TIERS = ((7500000, 'platinum', 2.0), (3000000, 'gold', 1.5), (1000000, 'silver', 1.25), (0, 'regular', 1.0))
REVIEW_NAMES = ['Dewi','Rizky','Anisa','Budi','Maya','Fajar','Sinta','Andre','Putri','Kevin','Laras','Hendra']
REVIEW_POOL = [
 (5,'Bahannya halus dan nyaman dipakai seharian. Sesuai ekspektasi.'),
 (5,'Potongannya rapi, ukuran pas sesuai tabel. Pasti beli lagi.'),
 (4,'Kualitas bagus untuk harganya. Warna sesuai foto.'),
 (5,'Adem, tidak gerah, cocok untuk cuaca Jakarta.'),
 (4,'Jahitan rapi dan tidak mudah kusut setelah dicuci.'),
 (5,'Dipakai untuk kuliah dan jalan-jalan, nyaman sekali.'),
 (4,'Ukurannya sedikit longgar, tapi justru enak dipakai.'),
 (5,'Simpel dan mudah dipadukan dengan outfit apa pun.'),
 (4,'Pengiriman cepat dan kemasan rapi. Produk sesuai deskripsi.'),
 (3,'Bagus, hanya warnanya sedikit lebih gelap dari foto.'),
 (5,'Tidak luntur setelah beberapa kali dicuci. Worth it!'),
 (4,'Cocok untuk harian, bahan lembut di kulit.'),
]

def migrate(db):
    """Additive-only schema update. Existing users/orders/products are not dropped."""
    def cols(table): return {r[1] for r in db.execute(f'PRAGMA table_info({table})')}
    additions = {
      'addresses': {'label': "TEXT NOT NULL DEFAULT 'Rumah'", 'is_default': 'INTEGER NOT NULL DEFAULT 0'},
      'reviews': {'source': "TEXT NOT NULL DEFAULT 'member'", 'is_sample': 'INTEGER NOT NULL DEFAULT 0', 'is_visible': 'INTEGER NOT NULL DEFAULT 1', 'moderated_at': 'INTEGER', 'moderated_by': 'TEXT', 'moderation_note': "TEXT NOT NULL DEFAULT ''"},
      'orders': {'completed_at': 'INTEGER', 'cancelled_at': 'INTEGER', 'net_eligible_amount': 'REAL NOT NULL DEFAULT 0', 'refund_amount': 'REAL NOT NULL DEFAULT 0'},
      'member_points': {'reference_key': 'TEXT', 'source': "TEXT NOT NULL DEFAULT 'legacy'", 'admin_id': 'INTEGER'},
      'users': {'is_active': 'INTEGER NOT NULL DEFAULT 1'},
      'feedback': {'status': "TEXT NOT NULL DEFAULT 'new'", 'admin_note': "TEXT NOT NULL DEFAULT ''", 'handled_at': 'INTEGER', 'handled_by': 'TEXT'},
    }
    for table, fields in additions.items():
        existing = cols(table)
        for name, decl in fields.items():
            if name not in existing: db.execute(f'ALTER TABLE {table} ADD COLUMN {name} {decl}')
    db.execute("CREATE UNIQUE INDEX IF NOT EXISTS ux_users_member_code ON users(member_code) WHERE member_code<>''")
    db.execute("CREATE UNIQUE INDEX IF NOT EXISTS ux_member_points_reference ON member_points(reference_key) WHERE reference_key IS NOT NULL")
    db.execute("CREATE UNIQUE INDEX IF NOT EXISTS ux_one_default_address ON addresses(user_id) WHERE is_default=1")
    db.execute("CREATE INDEX IF NOT EXISTS ix_reviews_visible_product ON reviews(product_id,is_visible,created_at)")
    db.execute("""UPDATE orders SET order_status=CASE lower(order_status)
      WHEN 'processing' THEN 'diproses' WHEN 'pending' THEN 'diproses'
      WHEN 'packed' THEN 'dikemas' WHEN 'shipped' THEN 'dikirim'
      WHEN 'completed' THEN 'selesai' WHEN 'complete' THEN 'selesai'
      WHEN 'cancelled' THEN 'dibatalkan' ELSE lower(order_status) END""")
    db.execute("""UPDATE orders SET payment_status=CASE lower(payment_status)
      WHEN 'success' THEN 'Paid' WHEN 'paid' THEN 'Paid' WHEN 'failed' THEN 'Failed'
      WHEN 'refunded' THEN 'Refunded' ELSE payment_status END""")
    # Existing member addresses: choose one default per member without changing address content.
    db.execute('''UPDATE addresses SET is_default=1 WHERE id IN
      (SELECT MIN(id) FROM addresses GROUP BY user_id)
      AND NOT EXISTS (SELECT 1 FROM addresses a2 WHERE a2.user_id=addresses.user_id AND a2.is_default=1)''')
    # Convert old UI roles to the agreed two-role model.
    if db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='admins'").fetchone():
        db.execute("UPDATE admins SET role='admin' WHERE role IN ('editor','viewer')")
    # Legacy safeguard: earlier clients awarded shopping points at checkout.
    # Keep old ledger rows, but append a correction until the order is both
    # completed and payment-verified. A zero-value marker prevents re-awarding
    # already valid legacy points after the migration.
    legacy_orders=db.execute('''SELECT o.id,o.user_id,o.order_status,o.payment_status,
      COALESCE(SUM(mp.points_delta),0) AS legacy_net
      FROM orders o JOIN member_points mp ON mp.order_id=o.id
      WHERE mp.source='legacy' GROUP BY o.id''').fetchall()
    for row in legacy_orders:
        net_points=int(row['legacy_net'] or 0)
        if net_points<=0: continue
        eligible=(str(row['order_status']).lower() in ('selesai','completed','complete')
                  and str(row['payment_status']).lower() in ('paid','dibayar'))
        if eligible:
            db.execute("INSERT OR IGNORE INTO member_points(user_id,order_id,points_delta,reason,created_at,reference_key,source) VALUES(?,?,?,?,?,?,?)",
              (row['user_id'],row['id'],0,'Penanda migrasi poin pesanan lama yang sudah valid',int(time.time()),'order-complete:'+str(row['id']),'migration'))
        else:
            db.execute("INSERT OR IGNORE INTO member_points(user_id,order_id,points_delta,reason,created_at,reference_key,source) VALUES(?,?,?,?,?,?,?)",
              (row['user_id'],row['id'],-net_points,'Koreksi migrasi: poin ditahan sampai pesanan selesai dan pembayaran diverifikasi',int(time.time()),'legacy-unearned:'+str(row['id']),'migration'))
    # Backfill order net amount from immutable pricing snapshot when available.
    for row in db.execute('SELECT id,subtotal,order_json,order_status FROM orders WHERE net_eligible_amount=0').fetchall():
        try:
            o=json.loads(row['order_json'] or '{}')
            net=max(0.0,float(o.get('subtotal',row['subtotal'] or 0))-float(o.get('memberDiscount',0) or 0)-float(o.get('voucherDiscount',0) or 0)-float(o.get('pointsDiscount',0) or 0))
            db.execute('UPDATE orders SET net_eligible_amount=? WHERE id=?',(net,row['id']))
            if str(row['order_status']).lower() in ('selesai','completed','complete'):
                db.execute('UPDATE orders SET completed_at=COALESCE(completed_at,?) WHERE id=?',(int(time.time()),row['id']))
        except (ValueError,TypeError): pass
    db.commit()


def _tier(spend):
    for threshold, name, mult in TIERS:
        if spend >= threshold: return name, mult
    return 'regular', 1.0

def _spend(db, user_id):
    return float(db.execute("SELECT COALESCE(SUM(net_eligible_amount),0) FROM orders WHERE user_id=? AND lower(order_status) IN ('selesai','completed','complete') AND lower(payment_status) NOT IN ('refunded','refund')",(user_id,)).fetchone()[0] or 0)

def _summary(db, user_id):
    # Level membership memakai belanja bersih pesanan selesai dan Paid.
    spend=_spend(db,user_id); tier,mult=_tier(spend)
    points=int(db.execute('SELECT COALESCE(SUM(points_delta),0) FROM member_points WHERE user_id=?',(user_id,)).fetchone()[0] or 0)
    # Ringkasan transaksi dan hemat harus memakai kohort yang sama: Paid,
    # tidak dibatalkan, dan tidak direfund. COD Unpaid tidak dihitung.
    eligible_sql="""user_id=? AND lower(payment_status) IN ('paid','dibayar')
      AND lower(order_status) NOT IN ('dibatalkan','cancelled')"""
    transaction_spend=float(db.execute('SELECT COALESCE(SUM(MAX(0,total_price-COALESCE(refund_amount,0))),0) FROM orders WHERE '+eligible_sql,(user_id,)).fetchone()[0] or 0)
    transaction_savings=0.0
    for row in db.execute('SELECT order_json FROM orders WHERE '+eligible_sql,(user_id,)):
        try:
            snap=json.loads(row['order_json'] or '{}')
            transaction_savings += sum(max(0.0,float(snap.get(k,0) or 0)) for k in ('memberDiscount','voucherDiscount','pointsDiscount','shippingDiscount'))
        except (ValueError,TypeError):
            pass
    return {'total_spend':spend,'transaction_spend':transaction_spend,
      'transaction_savings':transaction_savings,'tier':tier,'points':max(0,points),
      'next_tier': next(({'name':n,'minimum':t} for t,n,_ in reversed(TIERS) if t>spend),None)}


def _audit(db, admin, action, entity, entity_id, detail=''):
    try: actor = admin['username']
    except (KeyError, TypeError, IndexError): actor = 'system'
    db.execute('INSERT INTO audit_log(at,admin,action,entity,entity_id,detail) VALUES(?,?,?,?,?,?)',
      (int(time.time()), str(actor or 'system'), action, entity, str(entity_id), detail))

def _address_dict(r):
    d=dict(r); d['is_default']=bool(d.get('is_default')); return d

def handle_member(handler, method, path, user, data=None):
    """Returns (handled, status, payload). user is sqlite Row or None."""
    if not path.startswith('/api/member') and not path.startswith('/api/addresses') and not path.startswith('/api/reviews') and not path.startswith('/api/orders') and not path.startswith('/api/points'):
        return False,0,None
    if user is None: return True,401,{'error':'Sesi tidak valid. Silakan login kembali.'}
    uid=int(user['id']); store=handler.store; data=data or {}
    with store.lock, store.connect() as db:
        if method=='GET' and path=='/api/member/bootstrap':
            u=db.execute('SELECT * FROM users WHERE id=?',(uid,)).fetchone()
            addresses=[_address_dict(r) for r in db.execute('SELECT * FROM addresses WHERE user_id=? ORDER BY is_default DESC,id',(uid,))]
            cart=[dict(r) for r in db.execute('SELECT c.product_id,c.color_code,c.size,c.quantity,c.is_selected,p.name,p.price,p.image FROM cart_items c JOIN products p ON p.id=c.product_id WHERE c.user_id=?',(uid,))]
            wishlist=[r[0] for r in db.execute('SELECT product_id FROM wishlist WHERE user_id=?',(uid,))]
            orders=[]
            for o in db.execute('SELECT * FROM orders WHERE user_id=? ORDER BY order_date DESC',(uid,)):
                od=dict(o); od['snapshot']=json.loads(od.pop('order_json') or '{}')
                od['items']=[dict(i) for i in db.execute('SELECT * FROM order_items WHERE order_id=?',(od['id'],))]
                orders.append(od)
            activities=[dict(r) for r in db.execute('SELECT * FROM member_activities WHERE user_id=? ORDER BY created_at DESC',(uid,))]
            points=[dict(r) for r in db.execute('SELECT * FROM member_points WHERE user_id=? ORDER BY id DESC',(uid,))]
            reviews=[dict(r) for r in db.execute('SELECT * FROM reviews WHERE user_id=? AND is_visible=1 ORDER BY created_at DESC',(uid,))]
            return True,200,{'user':store._user(u),'addresses':addresses,'cart':cart,'wishlist':wishlist,'orders':orders,'activities':activities,'points_ledger':points,'reviews':reviews,'summary':_summary(db,uid)}
        if method=='GET' and path=='/api/addresses':
            return True,200,{'addresses':[_address_dict(r) for r in db.execute('SELECT * FROM addresses WHERE user_id=? ORDER BY is_default DESC,id',(uid,))]}
        if method=='POST' and path=='/api/addresses':
            required=('recipient_name','phone','address')
            if any(not str(data.get(k,'')).strip() for k in required): return True,400,{'error':'Nama penerima, telepon, dan alamat wajib diisi.'}
            is_default=bool(data.get('is_default'))
            if is_default: db.execute('UPDATE addresses SET is_default=0 WHERE user_id=?',(uid,))
            elif not db.execute('SELECT 1 FROM addresses WHERE user_id=? AND is_default=1',(uid,)).fetchone(): is_default=True
            cur=db.execute('INSERT INTO addresses(user_id,recipient_name,phone,address,city,postal_code,created_at,label,is_default) VALUES(?,?,?,?,?,?,?,?,?)',
              (uid,str(data['recipient_name']).strip(),str(data['phone']).strip(),str(data['address']).strip(),str(data.get('city','')).strip(),str(data.get('postal_code','')).strip(),int(time.time()),str(data.get('label') or 'Rumah')[:40],int(is_default)))
            if is_default: db.execute('UPDATE users SET address=? WHERE id=?',(str(data['address']).strip(),uid))
            db.commit(); row=db.execute('SELECT * FROM addresses WHERE id=?',(cur.lastrowid,)).fetchone(); return True,201,{'address':_address_dict(row)}
        if path.startswith('/api/addresses/'):
            bits=path.split('/'); aid=int(bits[3]) if len(bits)>3 and bits[3].isdigit() else -1
            row=db.execute('SELECT * FROM addresses WHERE id=? AND user_id=?',(aid,uid)).fetchone()
            if not row: return True,404,{'error':'Alamat tidak ditemukan.'}
            if method=='POST' and len(bits)>4 and bits[4]=='default':
                db.execute('UPDATE addresses SET is_default=0 WHERE user_id=?',(uid,)); db.execute('UPDATE addresses SET is_default=1 WHERE id=? AND user_id=?',(aid,uid))
                db.execute('UPDATE users SET address=? WHERE id=?',(row['address'],uid)); db.commit(); return True,200,{'ok':True}
            if method=='PUT':
                fields=['recipient_name','phone','address','city','postal_code','label']; vals=[str(data.get(k, row[k] if k in row.keys() else '')).strip() for k in fields]
                if not vals[0] or not vals[1] or not vals[2]: return True,400,{'error':'Nama, telepon, dan alamat wajib diisi.'}
                make_default=bool(data.get('is_default',row['is_default']))
                if make_default: db.execute('UPDATE addresses SET is_default=0 WHERE user_id=?',(uid,))
                db.execute('UPDATE addresses SET recipient_name=?,phone=?,address=?,city=?,postal_code=?,label=?,is_default=? WHERE id=? AND user_id=?',(*vals,int(make_default),aid,uid))
                if make_default:
                    db.execute('UPDATE users SET address=? WHERE id=?',(vals[2],uid))
                elif row['is_default']:
                    db.execute('UPDATE addresses SET is_default=1 WHERE id=(SELECT MIN(id) FROM addresses WHERE user_id=? AND id<>?)',(uid,aid))
                    alt=db.execute('SELECT address FROM addresses WHERE user_id=? AND is_default=1',(uid,)).fetchone()
                    db.execute('UPDATE users SET address=? WHERE id=?',(alt['address'] if alt else '',uid))
                db.commit()
                updated=db.execute('SELECT * FROM addresses WHERE id=? AND user_id=?',(aid,uid)).fetchone()
                return True,200,{'ok':True,'address':_address_dict(updated)}
            if method=='DELETE':
                was=bool(row['is_default']); db.execute('DELETE FROM addresses WHERE id=? AND user_id=?',(aid,uid))
                if was:
                    db.execute('UPDATE addresses SET is_default=1 WHERE id=(SELECT MIN(id) FROM addresses WHERE user_id=?)',(uid,))
                    alt=db.execute('SELECT address FROM addresses WHERE user_id=? AND is_default=1',(uid,)).fetchone()
                    db.execute('UPDATE users SET address=? WHERE id=?',(alt['address'] if alt else '',uid))
                db.commit(); return True,200,{'ok':True}
        # Simpan pilihan penerimaan pada server, bukan hanya cache Flutter.
        if method=='POST' and path.startswith('/api/orders/') and path.endswith('/fulfillment'):
            oid=path.split('/')[-2]
            o=db.execute('SELECT * FROM orders WHERE id=? AND user_id=?',(oid,uid)).fetchone()
            if not o: return True,404,{'error':'Pesanan tidak ditemukan.'}
            if str(o['order_status']).lower() not in ('diproses','processing'):
                return True,409,{'error':'Pilihan penerimaan hanya dapat diubah saat pesanan masih diproses.'}
            snapshot=json.loads(o['order_json'] or '{}')
            if snapshot.get('fulfillmentAt') or snapshot.get('fulfillmentType'):
                return True,409,{'error':'Pilihan penerimaan sudah disimpan.'}
            kind=str(data.get('type','')).lower()
            now=int(time.time())
            if kind in ('pickup','ambil_di_toko'):
                store_name=str(data.get('store_name','')).strip()
                store_address=str(data.get('store_address','')).strip()
                store_id=str(data.get('store_id') or '')
                # Daftar toko pickup pada aplikasi masih berupa data simulasi;
                # simpan snapshot pilihan yang dikirim Flutter tanpa FK ke katalog toko.
                if not store_name or not store_address:
                    return True,400,{'error':'Nama dan alamat toko wajib dipilih.'}
                snapshot.pop('addressId',None)
                snapshot.update({'fulfillmentType':'pickup','storeId':store_id or None,
                    'storeName':store_name,'storeAddress':store_address,
                    'pickupCode':snapshot.get('pickupCode') or ('PU-'+str(oid)[-4:]+'-'+str(uid).zfill(2)),
                    'deliveryService':None,'fulfillmentAt':time.strftime('%Y-%m-%dT%H:%M:%S',time.localtime(now)),
                    'shippingRefund':max(0.0,float(snapshot.get('shippingFee',0) or 0)-float(snapshot.get('shippingDiscount',0) or 0)),
                    'shippingFee':0,'shippingDiscount':0})
                shipping_refund=float(snapshot['shippingRefund'] or 0)
                db.execute('UPDATE orders SET address_id=NULL,order_json=?,refund_amount=MAX(COALESCE(refund_amount,0),?) WHERE id=?',
                    (json.dumps(snapshot,ensure_ascii=False),shipping_refund,oid))
            elif kind in ('delivery','diantar'):
                aid=int(data.get('address_id') or 0)
                addr=db.execute('SELECT * FROM addresses WHERE id=? AND user_id=?',(aid,uid)).fetchone()
                if not addr: return True,400,{'error':'Pilih alamat tersimpan milik akun Anda.'}
                snapshot.update({'addressId':aid,'fulfillmentType':'delivery','storeId':None,'storeName':None,'storeAddress':None,
                    'pickupCode':None,'deliveryService':str(data.get('delivery_service') or 'Reguler (2-4 hari kerja)'),
                    'recipient':addr['recipient_name'],'phone':addr['phone'],
                    'address':', '.join(x for x in [addr['address'],addr['city'],addr['postal_code']] if x),
                    'fulfillmentAt':time.strftime('%Y-%m-%dT%H:%M:%S',time.localtime(now)),'shippingRefund':0})
                db.execute('UPDATE orders SET address_id=?,order_json=? WHERE id=?',(aid,json.dumps(snapshot,ensure_ascii=False),oid))
            else:
                return True,400,{'error':'Jenis penerimaan tidak valid.'}
            db.commit()
            return True,200,{'ok':True,'order':snapshot}
        # Tombol pembayaran simulasi untuk pesanan yang masih Pending.
        if method=='POST' and path.startswith('/api/orders/') and path.endswith('/simulate-payment'):
            oid=path.split('/')[-2]
            o=db.execute('SELECT * FROM orders WHERE id=? AND user_id=?',(oid,uid)).fetchone()
            if not o: return True,404,{'error':'Pesanan tidak ditemukan.'}
            if 'cod' in str(o['payment_method'] or '').lower() or 'bayar di tempat' in str(o['payment_method'] or '').lower():
                return True,409,{'error':'Pesanan COD dibayar saat diterima dan tidak memakai simulasi pembayaran online.'}
            if str(o['payment_status']).lower() in ('paid','dibayar'):
                return True,200,{'ok':True,'payment_status':'Paid','already_paid':True}
            if str(o['payment_status']).lower() not in ('pending','menunggu'):
                return True,409,{'error':'Pembayaran tidak dapat disimulasikan pada status ini.'}
            snapshot=json.loads(o['order_json'] or '{}')
            snapshot['paymentStatus']='Paid'; snapshot['paymentSimulated']=True
            snapshot['paymentConfirmedAt']=time.strftime('%Y-%m-%dT%H:%M:%S',time.localtime())
            db.execute("UPDATE orders SET payment_status='Paid',order_json=? WHERE id=?",
                (json.dumps(snapshot,ensure_ascii=False),oid))
            db.commit()
            return True,200,{'ok':True,'payment_status':'Paid','simulated':True}
        if method=='GET' and path=='/api/orders':
            out=[]
            for o in db.execute('SELECT * FROM orders WHERE user_id=? ORDER BY order_date DESC',(uid,)):
                d=dict(o); d['snapshot']=json.loads(d.pop('order_json') or '{}'); d['items']=[dict(i) for i in db.execute('SELECT * FROM order_items WHERE order_id=?',(d['id'],))]; out.append(d)
            return True,200,{'orders':out}
        if method=='GET' and path.startswith('/api/orders/'):
            oid=path.rsplit('/',1)[-1]; o=db.execute('SELECT * FROM orders WHERE id=? AND user_id=?',(oid,uid)).fetchone()
            if not o: return True,404,{'error':'Pesanan tidak ditemukan.'}
            d=dict(o); d['snapshot']=json.loads(d.pop('order_json') or '{}'); d['items']=[dict(i) for i in db.execute('SELECT * FROM order_items WHERE order_id=?',(oid,))]; return True,200,{'order':d}
        if method=='POST' and path.startswith('/api/orders/') and path.endswith('/cancel'):
            oid=path.split('/')[-2]
            o=db.execute('SELECT * FROM orders WHERE id=? AND user_id=?',(oid,uid)).fetchone()
            if not o: return True,404,{'error':'Pesanan tidak ditemukan.'}
            current_status=str(o['order_status']).lower()
            cancellable_statuses=('diproses','processing','dikemas','packed','dikirim','shipped')
            if current_status not in cancellable_statuses:
                return True,409,{'error':'Pesanan yang sudah selesai atau dibatalkan tidak dapat dibatalkan lagi.'}
            now=int(time.time())
            was_paid=str(o['payment_status']).lower() in ('paid','dibayar')
            refund_amount=float(o['total_price'] or 0) if was_paid else 0.0
            db.execute("UPDATE orders SET order_status='dibatalkan',payment_status=?,cancelled_at=?,net_eligible_amount=0,refund_amount=? WHERE id=?",
                ('Refunded' if was_paid else o['payment_status'],now,refund_amount,oid))
            earned=db.execute("SELECT COALESCE(SUM(points_delta),0) FROM member_points WHERE reference_key=?",('order-complete:'+oid,)).fetchone()[0]
            if earned>0:
                db.execute("INSERT OR IGNORE INTO member_points(user_id,order_id,points_delta,reason,created_at,reference_key,source) VALUES(?,?,?,?,?,?,?)",
                    (uid,oid,-int(earned),'Koreksi poin karena pembatalan pesanan',now,'order-refund:'+oid,'refund'))
            redeemed=db.execute('SELECT COALESCE(SUM(-points_delta),0) FROM member_points WHERE reference_key=?',('order-redeem:'+oid,)).fetchone()[0]
            if redeemed>0:
                db.execute("INSERT OR IGNORE INTO member_points(user_id,order_id,points_delta,reason,created_at,reference_key,source) VALUES(?,?,?,?,?,?,?)",
                  (uid,oid,int(redeemed),'Pengembalian poin karena pembatalan pesanan',now,'order-redeem-refund:'+oid,'refund'))
            db.execute("INSERT OR IGNORE INTO member_activities(id,user_id,activity_type,title,detail,points,created_at) VALUES(?,?,?,?,?,?,?)",
              ('cancel-'+oid,uid,'cancel','Pesanan '+oid+' dibatalkan','Dibatalkan oleh member',0,time.strftime('%Y-%m-%dT%H:%M:%S')))
            db.commit(); return True,200,{'ok':True,'order_status':'dibatalkan','payment_status':'Refunded' if was_paid else o['payment_status'],'refund_amount':refund_amount,'simulated_refund':was_paid}
        if method=='POST' and path=='/api/points/checkin':
            from datetime import date, timedelta
            today=date.today().isoformat()
            row=db.execute('SELECT last_check_in_day,check_in_streak FROM users WHERE id=?',(uid,)).fetchone()
            if row['last_check_in_day']==today: return True,409,{'error':'Kamu sudah check-in hari ini.'}
            yesterday=(date.today()-timedelta(days=1)).isoformat()
            streak=(int(row['check_in_streak'] or 0)+1) if row['last_check_in_day']==yesterday else 1
            reward=min(15,5+2*max(0,streak-1)); now=int(time.time())
            db.execute('UPDATE users SET last_check_in_day=?,check_in_streak=? WHERE id=?',(today,streak,uid))
            db.execute("INSERT OR IGNORE INTO member_points(user_id,points_delta,reason,created_at,reference_key,source) VALUES(?,?,?,?,?,'checkin')",
              (uid,reward,'Check-in harian hari ke-'+str(streak),now,'checkin:'+str(uid)+':'+today))
            db.execute("INSERT OR IGNORE INTO member_activities(id,user_id,activity_type,title,detail,points,created_at) VALUES(?,?,?,?,?,?,?)",
              ('checkin-'+str(uid)+'-'+today,uid,'checkIn','Check-in harian','Hari ke-'+str(streak)+' berturut-turut',reward,time.strftime('%Y-%m-%dT%H:%M:%S')))
            db.commit(); return True,200,{'ok':True,'reward':reward,'streak':streak,'last_check_in_day':today}
        if method=='GET' and path=='/api/points':
            return True,200,{'summary':_summary(db,uid),'transactions':[dict(r) for r in db.execute('SELECT * FROM member_points WHERE user_id=? ORDER BY id DESC',(uid,))]}
        if method=='GET' and path=='/api/reviews':
            qs=parse_qs(handler.path.split('?',1)[1]) if '?' in handler.path else {}; pid=qs.get('product_id',[''])[0]
            if not pid: return True,400,{'error':'product_id wajib diisi.'}
            if pid == 'all':
                rows=db.execute('''SELECT r.id,r.product_id,r.author,r.rating,r.review_text,r.created_at,r.source,r.is_sample,u.member_code
                  FROM reviews r JOIN users u ON u.id=r.user_id WHERE r.is_visible=1 ORDER BY r.created_at DESC''').fetchall()
            else:
                rows=db.execute('''SELECT r.id,r.product_id,r.author,r.rating,r.review_text,r.created_at,r.source,r.is_sample,u.member_code
                  FROM reviews r JOIN users u ON u.id=r.user_id WHERE r.product_id=? AND r.is_visible=1 ORDER BY r.created_at DESC''',(pid,)).fetchall()
            return True,200,{'reviews':[dict(r) for r in rows]}
        if method=='POST' and path=='/api/reviews':
            pid=str(data.get('product_id','')); rating=int(data.get('rating',0) or 0); text=str(data.get('review_text','')).strip()
            if not db.execute('SELECT 1 FROM products WHERE id=?',(pid,)).fetchone(): return True,404,{'error':'Produk tidak ditemukan.'}
            if rating<1 or rating>5 or not text: return True,400,{'error':'Rating 1-5 dan isi ulasan wajib diisi.'}
            rid='member-%s-%s-%s'%(uid,pid,int(time.time()*1000))
            db.execute("INSERT INTO reviews(id,user_id,product_id,author,rating,review_text,created_at,source,is_sample,is_visible) VALUES(?,?,?,?,?,?,?,'member',0,1)",(rid,uid,pid,user['name'],rating,text,time.strftime('%Y-%m-%dT%H:%M:%S')))
            db.commit(); return True,201,{'ok':True,'id':rid}
    return False,0,None


def admin_handle(admin_obj, me, method, path, q, body):
    """Extra admin operations. Returns None if route not handled."""
    from admin import ApiError, Admin
    parts=[p for p in path.split('/') if p][2:]
    if not parts: return None
    if parts[0]=='orders' and len(parts)==2 and method=='GET':
        oid=parts[1]
        with admin_obj.store.connect() as db:
            row=db.execute('SELECT o.*,u.name AS customer,u.email,u.phone AS customer_phone FROM orders o JOIN users u ON u.id=o.user_id WHERE o.id=?',(oid,)).fetchone()
            if not row: raise ApiError(404,'Pesanan tidak ditemukan.')
            order=dict(row); order['snapshot']=json.loads(order.get('order_json') or '{}')
            order['items']=[dict(x) for x in db.execute('SELECT * FROM order_items WHERE order_id=?',(oid,))]
            if order.get('address_id'):
                addr=db.execute('SELECT * FROM addresses WHERE id=?',(order['address_id'],)).fetchone()
                order['address_current']=dict(addr) if addr else None
        return {'order':order}
    if parts[0]=='orders' and len(parts)==3 and parts[2]=='status' and method=='POST':
        Admin.need(me,'admin')
        oid=parts[1]; status=str(body.get('order_status','')).lower(); pay=str(body.get('payment_status',''))
        valid={'diproses','dikemas','dikirim','selesai','dibatalkan'}
        if status not in valid: raise ApiError(400,'Status pesanan tidak valid.')
        if pay and pay.lower() not in {'pending','unpaid','paid','failed','refunded','menunggu','dibayar','gagal','refund'}: raise ApiError(400,'Status pembayaran tidak valid.')
        with admin_obj.store.lock, admin_obj.store.connect() as db:
            o=db.execute('SELECT * FROM orders WHERE id=?',(oid,)).fetchone()
            if not o: raise ApiError(404,'Pesanan tidak ditemukan.')
            old_raw=str(o['order_status']).lower()
            old={'processing':'diproses','packed':'dikemas','shipped':'dikirim','completed':'selesai','cancelled':'dibatalkan'}.get(old_raw,old_raw)
            now=int(time.time()); net=float(o['net_eligible_amount'] or 0)
            new_pay=pay or o['payment_status']
            if status=='dibatalkan' and str(new_pay).lower() in ('paid','dibayar'):
                new_pay='Refunded'
            transitions={'diproses':{'diproses','dikemas','dibatalkan'},'dikemas':{'dikemas','dikirim','dibatalkan'},
              'dikirim':{'dikirim','selesai','dibatalkan'},'selesai':{'selesai','dibatalkan'},'dibatalkan':{'dibatalkan'}}
            if status not in transitions.get(old,{old}):
                raise ApiError(409,'Urutan status tidak valid. Gunakan Diproses → Dikemas → Dikirim → Selesai.')
            refund_amount=float(o['total_price'] or 0) if str(new_pay).lower() in ('refunded','refund') else float(o['refund_amount'] or 0)
            db.execute('UPDATE orders SET order_status=?,payment_status=?,completed_at=?,cancelled_at=?,refund_amount=? WHERE id=?',
              (status,new_pay,now if status=='selesai' else o['completed_at'],now if status=='dibatalkan' else o['cancelled_at'],refund_amount,oid))
            already_awarded=db.execute('SELECT 1 FROM member_points WHERE reference_key=?',('order-complete:'+oid,)).fetchone()
            if status=='selesai' and new_pay.lower() in ('paid','dibayar') and not already_awarded:
                prior=_spend(db,o['user_id'])-net; tier,mult=_tier(max(0,prior)); earned=math.floor(max(0,net)/10000*mult)
                if earned:
                    db.execute("INSERT OR IGNORE INTO member_points(user_id,order_id,points_delta,reason,created_at,reference_key,source) VALUES(?,?,?,?,?,?,?)",
                      (o['user_id'],oid,earned,'Poin pesanan selesai',now,'order-complete:'+oid,'order'))
            if status=='dibatalkan' or new_pay.lower() in ('refunded','refund'):
                earned=db.execute("SELECT COALESCE(SUM(points_delta),0) FROM member_points WHERE reference_key=?",('order-complete:'+oid,)).fetchone()[0]
                if earned>0:
                    db.execute("INSERT OR IGNORE INTO member_points(user_id,order_id,points_delta,reason,created_at,reference_key,source) VALUES(?,?,?,?,?,?,?)",
                      (o['user_id'],oid,-int(earned),'Koreksi poin karena pembatalan/refund',now,'order-refund:'+oid,'refund'))
                    db.execute('UPDATE orders SET net_eligible_amount=0 WHERE id=?',(oid,))
                redeemed=db.execute("SELECT COALESCE(SUM(-points_delta),0) FROM member_points WHERE reference_key=?",('order-redeem:'+oid,)).fetchone()[0]
                if redeemed>0:
                    db.execute("INSERT OR IGNORE INTO member_points(user_id,order_id,points_delta,reason,created_at,reference_key,source) VALUES(?,?,?,?,?,?,?)",
                      (o['user_id'],oid,int(redeemed),'Pengembalian poin karena pembatalan/refund',now,'order-redeem-refund:'+oid,'refund'))
            _audit(db,me,'update_status','order',oid,f'{old} -> {status}; payment={new_pay}')
            db.commit()
            if broadcast_admin_event:
                broadcast_admin_event('order_updated', {'id': oid, 'status': status, 'payment_status': new_pay})
        return {'ok':True,'order_status':status,'payment_status':new_pay}
    if parts[0]=='points' and len(parts)==2 and parts[1]=='adjust' and method=='POST':
        Admin.need(me,'admin'); uid=int(body.get('user_id',0)); delta=int(body.get('points_delta',0)); reason=str(body.get('reason','')).strip()
        if not uid or not delta or not reason: raise ApiError(400,'user_id, points_delta, dan reason wajib diisi.')
        with admin_obj.store.lock, admin_obj.store.connect() as db:
            if not db.execute('SELECT 1 FROM users WHERE id=?',(uid,)).fetchone(): raise ApiError(404,'Member tidak ditemukan.')
            balance=int(db.execute('SELECT COALESCE(SUM(points_delta),0) FROM member_points WHERE user_id=?',(uid,)).fetchone()[0] or 0)
            if balance + delta < 0: raise ApiError(400,'Koreksi tidak boleh membuat saldo poin member negatif.')
            cur=db.execute("INSERT INTO member_points(user_id,points_delta,reason,created_at,reference_key,source,admin_id) VALUES(?,?,?,?,?,?,?)",
              (uid,delta,reason,int(time.time()),'admin-adjust:'+str(uid)+':'+str(time.time_ns()),'admin',me['id']))
            _audit(db,me,'adjust_points','member',uid,f'{delta}: {reason}'); db.commit()
        return {'ok':True}
    if parts[0]=='reviews' and len(parts)==3 and parts[2]=='visibility' and method=='PUT':
        Admin.need(me,'admin'); rid=parts[1]; visible=1 if body.get('is_visible') else 0; note=str(body.get('note',''))
        with admin_obj.store.lock, admin_obj.store.connect() as db:
            cur=db.execute('UPDATE reviews SET is_visible=?,moderated_at=?,moderated_by=?,moderation_note=? WHERE id=?',
              (visible,int(time.time()),str(me['username']),note,rid))
            if not cur.rowcount: raise ApiError(404,'Ulasan tidak ditemukan.')
            _audit(db,me,'moderate','review',rid,'visible' if visible else 'hidden'); db.commit()
        return {'ok':True}
    if parts[0]=='addresses' and len(parts)==2 and method in ('PUT','DELETE'):
        Admin.need(me,'admin'); aid=int(parts[1])
        with admin_obj.store.lock, admin_obj.store.connect() as db:
            row=db.execute('SELECT * FROM addresses WHERE id=?',(aid,)).fetchone()
            if not row: raise ApiError(404,'Alamat tidak ditemukan.')
            if method=='PUT':
                fields=('recipient_name','phone','address','city','postal_code','label')
                vals=[str(body.get(k,row[k] if k in row.keys() else '')).strip() for k in fields]
                if not vals[0] or not vals[1] or not vals[2]: raise ApiError(400,'Penerima, telepon, dan alamat wajib diisi.')
                make_default=bool(body.get('is_default',row['is_default']))
                if make_default: db.execute('UPDATE addresses SET is_default=0 WHERE user_id=?',(row['user_id'],))
                db.execute('UPDATE addresses SET recipient_name=?,phone=?,address=?,city=?,postal_code=?,label=?,is_default=? WHERE id=?',(*vals,int(make_default),aid))
                if make_default:
                    db.execute('UPDATE users SET address=? WHERE id=?',(vals[2],row['user_id']))
                elif row['is_default']:
                    db.execute('UPDATE addresses SET is_default=1 WHERE id=(SELECT MIN(id) FROM addresses WHERE user_id=? AND id<>?)',(row['user_id'],aid))
                    alt=db.execute('SELECT address FROM addresses WHERE user_id=? AND is_default=1',(row['user_id'],)).fetchone()
                    db.execute('UPDATE users SET address=? WHERE id=?',(alt['address'] if alt else '',row['user_id']))
                _audit(db,me,'update','address',aid,'Alamat member diperbarui')
            else:
                if row['is_default']:
                    db.execute('UPDATE addresses SET is_default=0 WHERE id=?',(aid,))
                    db.execute('UPDATE addresses SET is_default=1 WHERE id=(SELECT MIN(id) FROM addresses WHERE user_id=? AND id<>?)',(row['user_id'],aid))
                    alt=db.execute('SELECT address FROM addresses WHERE user_id=? AND is_default=1',(row['user_id'],)).fetchone()
                    db.execute('UPDATE users SET address=? WHERE id=?',(alt['address'] if alt else '',row['user_id']))
                db.execute('DELETE FROM addresses WHERE id=?',(aid,))
                _audit(db,me,'delete','address',aid,'Alamat member dihapus')
            db.commit()
        return {'ok':True}
    if parts[0]=='feedback' and len(parts)==3 and parts[2]=='status' and method=='PUT':
        Admin.need(me,'admin'); fid=int(parts[1]); status=str(body.get('status','new')).lower(); note=str(body.get('admin_note',''))
        if status not in ('new','in_progress','resolved'): raise ApiError(400,'Status feedback tidak valid.')
        with admin_obj.store.lock, admin_obj.store.connect() as db:
            cur=db.execute('UPDATE feedback SET status=?,admin_note=?,handled_at=?,handled_by=? WHERE id=?',
              (status,note,int(time.time()),str(me['username']),fid))
            if not cur.rowcount: raise ApiError(404,'Feedback tidak ditemukan.')
            _audit(db,me,'follow_up','feedback',fid,status+': '+note); db.commit()
        return {'ok':True}
    if parts[0]=='admins' and len(parts)==2 and method=='DELETE':
        Admin.need(me,'owner'); aid=int(parts[1]); password=str(body.get('confirm_password',''))
        with admin_obj.store.lock, admin_obj.store.connect() as db:
            current=db.execute('SELECT * FROM admins WHERE id=?',(me['id'],)).fetchone()
            target=db.execute('SELECT * FROM admins WHERE id=?',(aid,)).fetchone()
            if not target: raise ApiError(404,'Admin tidak ditemukan.')
            if aid==me['id']: raise ApiError(400,'Tidak boleh menghapus akun sendiri.')
            if not password or not __import__('hmac').compare_digest(__import__('admin')._hash(password,current['salt']),current['password_hash']):
                raise ApiError(401,'Password akun Owner yang sedang login salah.')
            if target['role']=='owner' and db.execute("SELECT COUNT(*) FROM admins WHERE role='owner' AND active=1").fetchone()[0]<=1:
                raise ApiError(400,'Owner terakhir tidak boleh dihapus.')
            _audit(db,me,'delete','admin',aid,target['username']); db.execute('DELETE FROM admins WHERE id=?',(aid,)); db.commit()
        return {'ok':True}
    return None

def seed_sample_reviews(db):
    """Move deterministic sample review content into reviews and link real sample accounts."""
    accounts={r['name']:r['id'] for r in db.execute('SELECT id,name FROM users') if r['name'] in REVIEW_NAMES}
    if len(accounts)<12: return 0
    products=[r[0] for r in db.execute('SELECT id FROM products ORDER BY id')]
    inserted=0
    from datetime import date, timedelta
    base=date(2026,9,20)
    for pid in products:
        try: seed=int(pid)
        except (ValueError,TypeError): seed=int.from_bytes(hashlib.sha256(str(pid).encode()).digest()[:4],'big')
        for i in range(3):
            rating,text=REVIEW_POOL[(seed*5+i*4)%len(REVIEW_POOL)]
            author=REVIEW_NAMES[(seed*3+i*5)%len(REVIEW_NAMES)]
            created=(base-timedelta(days=4+i*9+seed%5)).isoformat()
            cur=db.execute("""INSERT OR IGNORE INTO reviews(id,user_id,product_id,author,rating,review_text,created_at,source,is_sample,is_visible)
                VALUES(?,?,?,?,?,?,?,'sample',1,1)""",('sample-%s-%d'%(pid,i),accounts[author],pid,author,rating,text,created))
            inserted+=cur.rowcount
    return inserted


def safe_sync_member_data(store, user_id, payload):
    """One-way client cache sync: never accepts balances/statuses as authority."""
    lists=('cart','wishlist','orders','activities','reviews')
    if not all(isinstance(payload.get(k,[]),list) for k in lists): raise ValueError('Snapshot member harus berupa daftar.')
    now=int(time.time()); member=payload.get('member') if isinstance(payload.get('member'),dict) else {}
    with store.lock, store.connect() as db:
        for k in ('name','phone'):
            if k in member and str(member[k]).strip(): db.execute(f'UPDATE users SET {k}=? WHERE id=?',(str(member[k]).strip(),user_id))
        # Bonus poin, tier, saldo poin, dan status pesanan tidak pernah diterima dari Flutter.
        if 'address' in member:
            profile_address=str(member.get('address') or '').strip()
            before=db.execute('SELECT address FROM users WHERE id=?',(user_id,)).fetchone()
            address_changed=before and profile_address != str(before['address'] or '').strip()
            db.execute('UPDATE users SET address=? WHERE id=?',(profile_address,user_id))
            if address_changed and profile_address:
                # Sinkronisasi profil hanya memperbarui alamat utama yang ada;
                # tidak boleh membuat alamat baru. Pembuatan baru hanya lewat POST /api/addresses.
                user_row=db.execute('SELECT name,phone FROM users WHERE id=?',(user_id,)).fetchone()
                primary=db.execute('SELECT id FROM addresses WHERE user_id=? AND is_default=1 ORDER BY id LIMIT 1',(user_id,)).fetchone()
                if primary and user_row:
                    db.execute('UPDATE addresses SET recipient_name=?,phone=?,address=? WHERE id=? AND user_id=?',
                      (user_row['name'],user_row['phone'],profile_address,primary['id'],user_id))
        db.execute('DELETE FROM cart_items WHERE user_id=?',(user_id,))
        for item in payload.get('cart',[]):
            if not isinstance(item,dict): continue
            pid=str(item.get('product_id',''))
            if not db.execute('SELECT 1 FROM products WHERE id=?',(pid,)).fetchone(): continue
            db.execute('INSERT OR REPLACE INTO cart_items(user_id,product_id,color_code,size,quantity,is_selected,updated_at) VALUES(?,?,?,?,?,?,?)',
              (user_id,pid,str(item.get('color_code','')),str(item.get('size','')),max(1,min(99,int(item.get('quantity',1)))),int(bool(item.get('is_selected',True))),now))
        db.execute('DELETE FROM wishlist WHERE user_id=?',(user_id,))
        for pid in payload.get('wishlist',[]):
            if db.execute('SELECT 1 FROM products WHERE id=?',(str(pid),)).fetchone():
                db.execute('INSERT OR IGNORE INTO wishlist(user_id,product_id,created_at) VALUES(?,?,?)',(user_id,str(pid),now))
        # Order records are insert-only from member sync. Existing server status and snapshot are immutable here.
        for order in payload.get('orders',[]):
            if not isinstance(order,dict) or not order.get('id'): continue
            oid=str(order['id'])
            if db.execute('SELECT 1 FROM orders WHERE id=?',(oid,)).fetchone(): continue
            items=order.get('items',[]) if isinstance(order.get('items',[]),list) else []
            subtotal=float(order.get('subtotal',0) or 0)
            net=max(0.0,subtotal-float(order.get('memberDiscount',0) or 0)-float(order.get('voucherDiscount',0) or 0)-float(order.get('pointsDiscount',0) or 0))
            # Relasi order ke buku alamat hanya melalui addressId yang valid.
            # Teks alamat historis tetap disimpan sebagai snapshot pada order_json;
            # jangan pernah menambah baris addresses otomatis dari pesanan.
            address_id=None
            requested_address_id=order.get('addressId')
            if requested_address_id is not None:
                try:
                    existing=db.execute('SELECT id FROM addresses WHERE id=? AND user_id=?',
                        (int(requested_address_id),user_id)).fetchone()
                except (TypeError,ValueError):
                    existing=None
                if existing: address_id=existing['id']
            total=float(order.get('total',order.get('totalPrice',net+float(order.get('shippingFee',0) or 0)-float(order.get('shippingDiscount',0) or 0)+float(order.get('shippingRefund',0) or 0))) or 0)
            created=str(order.get('createdAt') or time.strftime('%Y-%m-%dT%H:%M:%S'))
            snapshot=dict(order); snapshot['server_imported']=True; snapshot['addressId']=address_id
            cancelled=bool(order.get('cancelledAt'))
            points_used=0 if cancelled else max(0,int(order.get('pointsUsed',0) or 0))
            balance=int(db.execute('SELECT COALESCE(SUM(points_delta),0) FROM member_points WHERE user_id=?',(user_id,)).fetchone()[0] or 0)
            if points_used>balance:
                raise ValueError('Saldo poin server tidak cukup untuk pesanan '+oid)
            payment_method=str(order.get('paymentMethod','')).strip()
            is_cod=('cod' in payment_method.lower() or 'bayar di tempat' in payment_method.lower())
            # Order dibuat setelah gateway sandbox sukses. Non-COD langsung Paid;
            # COD belum dibayar sampai barang diterima.
            gateway_confirmed=bool(str(order.get('gatewayRef') or '').strip())
            payment_status='Unpaid' if is_cod else ('Paid' if gateway_confirmed else 'Pending')
            if cancelled and payment_status=='Paid': payment_status='Refunded'
            snapshot['paymentStatus']=payment_status
            snapshot['paymentSimulated']=gateway_confirmed and not is_cod
            db.execute('''INSERT INTO orders(id,user_id,address_id,order_date,subtotal,total_price,payment_method,payment_status,order_status,order_json,net_eligible_amount)
              VALUES(?,?,?,?,?,?,?,?,?,?,?)''',(oid,user_id,address_id,created,subtotal,total,payment_method,payment_status,
              'dibatalkan' if cancelled else 'diproses',json.dumps(snapshot,ensure_ascii=False),0 if cancelled else net))
            if broadcast_admin_event and not cancelled:
                broadcast_admin_event('new_order', {'id': oid, 'total': total, 'user_id': user_id, 'payment_method': payment_method})
            if cancelled:
                db.execute('UPDATE orders SET cancelled_at=? WHERE id=?',(now,oid))
            if points_used:
                db.execute("INSERT OR IGNORE INTO member_points(user_id,order_id,points_delta,reason,created_at,reference_key,source) VALUES(?,?,?,?,?,?,?)",
                  (user_id,oid,-points_used,'Penukaran poin saat checkout',now,'order-redeem:'+oid,'redemption'))
            for item in items:
                if not isinstance(item,dict): continue
                pid=str(item.get('productId','')); exists=db.execute('SELECT 1 FROM products WHERE id=?',(pid,)).fetchone(); pid=pid if exists else None
                price=float(item.get('price',0) or 0); qty=max(1,int(item.get('quantity',1) or 1))
                db.execute('INSERT INTO order_items(order_id,product_id,product_name,image,size,color_value,price,quantity,subtotal) VALUES(?,?,?,?,?,?,?,?,?)',
                  (oid,pid,str(item.get('name','Produk')),str(item.get('image','')),str(item.get('size','')),item.get('colorValue'),price,qty,price*qty))
        for a in payload.get('activities',[]):
            if not isinstance(a,dict) or not a.get('id'): continue
            if str(a.get('type','')) == 'checkIn': continue  # dibuat oleh endpoint check-in server
            db.execute('INSERT OR IGNORE INTO member_activities(id,user_id,activity_type,title,detail,points,created_at) VALUES(?,?,?,?,?,?,?)',
              (str(a['id']),user_id,str(a.get('type','other')),str(a.get('title','Aktivitas')),str(a.get('detail','')),0,str(a.get('at',''))))
        for r in payload.get('reviews',[]):
            if not isinstance(r,dict) or not r.get('id'): continue
            pid=str(r.get('productId',''))
            if not db.execute('SELECT 1 FROM products WHERE id=?',(pid,)).fetchone(): continue
            db.execute("INSERT OR IGNORE INTO reviews(id,user_id,product_id,author,rating,review_text,created_at,source,is_sample,is_visible) VALUES(?,?,?,?,?,?,?,'member',0,1)",
              (str(r['id']),user_id,str(pid),str(r.get('author',member.get('name','Member'))),max(1,min(5,int(r.get('rating',5)))),str(r.get('text','')),str(r.get('at',''))))
        db.commit()
    return {'ok':True,'server_authoritative':True}
