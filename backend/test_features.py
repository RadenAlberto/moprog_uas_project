"""Integration tests for UNIQLO+ member/order/admin extensions."""
import json
import secrets
import shutil
import sqlite3
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
from pathlib import Path

import admin
import server


class FeatureIntegrationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.db_path = Path(cls.tmp.name) / 'features.sqlite3'
        shutil.copy2(Path(__file__).parent / 'uniqlo_plus.sqlite3', cls.db_path)
        cls.httpd = server.make_server('127.0.0.1', 0, cls.db_path)
        cls.base = f'http://127.0.0.1:{cls.httpd.server_address[1]}'
        cls.thread = threading.Thread(target=cls.httpd.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown(); cls.httpd.server_close(); cls.tmp.cleanup()

    def call(self, method, path, body=None, token=None):
        data = None if body is None else json.dumps(body).encode('utf8')
        headers = {'Content-Type': 'application/json'}
        if token: headers['Authorization'] = 'Bearer ' + token
        req = urllib.request.Request(self.base + path, data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=20) as response:
                return response.status, json.loads(response.read() or b'{}')
        except urllib.error.HTTPError as error:
            return error.code, json.loads(error.read() or b'{}')

    def setUp(self):
        status, body = self.call('POST', '/api/auth/register', {
            'name': 'Feature Tester', 'email': f'feature.{time.time_ns()}@example.com',
            'phone': '081234567890', 'password': 'password123',
            'member_code': 'UNQ-FEATURE-' + str(time.time_ns()),
        })
        self.assertEqual(status, 201, body)
        self.member_token = body['token']
        self.member_id = body['user']['id']
        salt = secrets.token_hex(16)
        with server.Handler.store.connect() as db:
            db.execute('INSERT OR IGNORE INTO admins(username,name,password_hash,salt,role,created_at,active) VALUES(?,?,?,?,?,?,1)',
                ('feature-owner', 'Feature Owner', admin._hash('OwnerPass123!', salt), salt, 'owner', int(time.time())))
            db.commit()
        status, login = self.call('POST', '/admin/api/login', {
            'username': 'feature-owner', 'password': 'OwnerPass123!'
        })
        self.assertEqual(status, 200, login)
        self.admin_token = login['token']
        self.admin_id = login['admin']['id']

    def test_sample_reviews_are_migrated_and_linked(self):
        status, body = self.call('GET', '/api/reviews?product_id=all', token=self.member_token)
        self.assertEqual(status, 200)
        self.assertGreaterEqual(len(body['reviews']), 4128)
        sample = [r for r in body['reviews'] if r['source'] == 'sample']
        self.assertEqual(len(sample), 4128)
        self.assertEqual({r['author'] for r in sample}, {
            'Dewi','Rizky','Anisa','Budi','Maya','Fajar','Sinta','Andre','Putri','Kevin','Laras','Hendra'
        })

    def test_address_book_has_one_default(self):
        status, first = self.call('POST', '/api/addresses', {
            'recipient_name':'Tester','phone':'0812','address':'Jalan Satu','is_default':True
        }, self.member_token)
        self.assertEqual(status, 201, first)
        first_id = first['address']['id']
        status, second = self.call('POST', '/api/addresses', {
            'recipient_name':'Tester','phone':'0812','address':'Jalan Dua'
        }, self.member_token)
        self.assertEqual(status, 201, second)
        status, rows = self.call('GET', '/api/addresses', token=self.member_token)
        self.assertEqual(status, 200)
        self.assertEqual(sum(1 for a in rows['addresses'] if a['is_default']), 1)
        self.assertEqual(self.call('POST', f"/api/addresses/{second['address']['id']}/default", {}, self.member_token)[0], 200)
        code, updated = self.call('PUT', f"/api/addresses/{second['address']['id']}", {
            'recipient_name':'Tester Updated','phone':'08129999','address':'Jalan Dua Updated',
            'city':'Jakarta','postal_code':'12345','label':'Kos','is_default':True
        }, self.member_token)
        self.assertEqual(code,200,updated)
        self.assertEqual(updated['address']['id'],second['address']['id'])
        self.assertEqual(updated['address']['address'],'Jalan Dua Updated')
        status, rows = self.call('GET', '/api/addresses', token=self.member_token)
        self.assertEqual([a['id'] for a in rows['addresses'] if a['is_default']], [second['address']['id']])
        self.assertEqual(self.call('DELETE', f'/api/addresses/{first_id}', token=self.member_token)[0], 200)

    def test_points_awarded_once_only_after_paid_completed_order(self):
        product_id = 'E495975-000'
        snapshot = {'cart': [], 'wishlist': [], 'activities': [], 'reviews': [], 'member': {}, 'orders': [{
            'id':'FEATURE-ORDER-1','createdAt':'2026-11-23T10:00:00','subtotal':100000,
            'memberDiscount':0,'voucherDiscount':0,'pointsDiscount':0,'pointsUsed':0,
            'shippingFee':15000,'items':[{'productId':product_id,'name':'Test product','price':100000,'quantity':1,'size':'M'}]
        }]}
        self.assertEqual(self.call('POST','/api/member/sync',snapshot,self.member_token)[0],200)
        for status in ('dikemas','dikirim','selesai'):
            code, body = self.call('POST','/admin/api/orders/FEATURE-ORDER-1/status',
                {'order_status':status,'payment_status':'Paid'},self.admin_token)
            self.assertEqual(code,200,body)
        self.assertEqual(self.call('POST','/admin/api/orders/FEATURE-ORDER-1/status',
            {'order_status':'selesai','payment_status':'Paid'},self.admin_token)[0],200)
        status, points = self.call('GET','/api/points',token=self.member_token)
        self.assertEqual(status,200)
        # 200 welcome points + 10 points from Rp100.000 regular-tier completed spend.
        self.assertEqual(points['summary']['points'],210)
        self.assertEqual(points['summary']['total_spend'],100000)

    def test_member_can_simulate_payment_choose_delivery_and_cancel_with_refund(self):
        code, address = self.call('POST','/api/addresses',{
            'recipient_name':'Tester','phone':'081234567890','address':'Jalan Simulasi 10',
            'city':'Jakarta','postal_code':'12345','is_default':True
        },self.member_token)
        self.assertEqual(code,201,address)
        aid=address['address']['id']
        snapshot={'cart':[],'wishlist':[],'activities':[],'reviews':[],'member':{},'orders':[{
            'id':'FULFILL-DELIVERY-1','createdAt':'2026-11-23T10:00:00','subtotal':100000,
            'total':115000,'memberDiscount':0,'voucherDiscount':0,'pointsDiscount':0,'pointsUsed':0,
            'shippingFee':15000,'shippingDiscount':0,'addressId':aid,'recipient':'Tester',
            'phone':'081234567890','address':'Jalan Simulasi 10, Jakarta, 12345',
            'items':[{'productId':'E495975-000','name':'Test','price':100000,'quantity':1,'size':'M'}]
        }]}
        self.assertEqual(self.call('POST','/api/member/sync',snapshot,self.member_token)[0],200)
        code, address_rows=self.call('GET','/api/addresses',token=self.member_token)
        self.assertEqual(code,200)
        self.assertEqual(len(address_rows['addresses']),1,'sync order tidak boleh membuat alamat duplikat')
        code, paid=self.call('POST','/api/orders/FULFILL-DELIVERY-1/simulate-payment',{},self.member_token)
        self.assertEqual(code,200,paid)
        code, saved=self.call('POST','/api/orders/FULFILL-DELIVERY-1/fulfillment',{
            'type':'delivery','address_id':aid,'delivery_service':'Reguler'
        },self.member_token)
        self.assertEqual(code,200,saved)
        code, boot=self.call('GET','/api/member/bootstrap',token=self.member_token)
        self.assertEqual(code,200)
        row=next(x for x in boot['orders'] if x['id']=='FULFILL-DELIVERY-1')
        self.assertEqual(row['payment_status'],'Paid')
        self.assertEqual(row['snapshot']['fulfillmentType'],'delivery')
        code, cancelled=self.call('POST','/api/orders/FULFILL-DELIVERY-1/cancel',{},self.member_token)
        self.assertEqual(code,200,cancelled)
        self.assertEqual(cancelled['payment_status'],'Refunded')
        self.assertTrue(cancelled['simulated_refund'])


    def test_member_can_cancel_any_unfinished_order_but_not_completed(self):
        orders=[]
        for oid in ('CANCEL-PACKED-1','CANCEL-SHIPPED-1','CANCEL-COMPLETED-1'):
            orders.append({
                'id':oid,'createdAt':'2026-11-23T10:00:00','subtotal':100000,
                'total':115000,'memberDiscount':0,'voucherDiscount':0,
                'pointsDiscount':0,'pointsUsed':0,'shippingFee':15000,
                'shippingDiscount':0,'paymentMethod':'Virtual Account BCA',
                'gatewayRef':'TRX-'+oid,
                'items':[{'productId':'E495975-000','name':'Test','price':100000,
                          'quantity':1,'size':'M'}]
            })
        payload={'cart':[],'wishlist':[],'activities':[],'reviews':[],
                 'member':{},'orders':orders}
        self.assertEqual(self.call('POST','/api/member/sync',payload,self.member_token)[0],200)
        with server.Handler.store.connect() as db:
            db.execute("UPDATE orders SET order_status='dikemas' WHERE id='CANCEL-PACKED-1'")
            db.execute("UPDATE orders SET order_status='dikirim' WHERE id='CANCEL-SHIPPED-1'")
            db.execute("UPDATE orders SET order_status='selesai' WHERE id='CANCEL-COMPLETED-1'")
            db.commit()

        for oid in ('CANCEL-PACKED-1','CANCEL-SHIPPED-1'):
            code, result=self.call('POST',f'/api/orders/{oid}/cancel',{},self.member_token)
            self.assertEqual(code,200,result)
            self.assertEqual(result['order_status'],'dibatalkan')
            self.assertEqual(result['payment_status'],'Refunded')

        code, result=self.call('POST','/api/orders/CANCEL-COMPLETED-1/cancel',{},self.member_token)
        self.assertEqual(code,409,result)

    def test_member_can_save_pickup_fulfillment_snapshot(self):
        snapshot={'cart':[],'wishlist':[],'activities':[],'reviews':[],'member':{},'orders':[{
            'id':'FULFILL-PICKUP-1','createdAt':'2026-11-23T10:00:00','subtotal':50000,
            'total':50000,'memberDiscount':0,'voucherDiscount':0,'pointsDiscount':0,'pointsUsed':0,
            'shippingFee':15000,'shippingDiscount':0,
            'items':[{'productId':'E495975-000','name':'Test','price':50000,'quantity':1,'size':'M'}]
        }]}
        self.assertEqual(self.call('POST','/api/member/sync',snapshot,self.member_token)[0],200)
        code, result=self.call('POST','/api/orders/FULFILL-PICKUP-1/fulfillment',{
            'type':'pickup','store_id':'s1','store_name':'UNIQLO Grand Indonesia',
            'store_address':'Jl. MH Thamrin'
        },self.member_token)
        self.assertEqual(code,200,result)
        code, boot=self.call('GET','/api/member/bootstrap',token=self.member_token)
        self.assertEqual(code,200)
        row=next(x for x in boot['orders'] if x['id']=='FULFILL-PICKUP-1')
        self.assertEqual(row['snapshot']['fulfillmentType'],'pickup')
        self.assertEqual(row['snapshot']['storeName'],'UNIQLO Grand Indonesia')
        with server.Handler.store.connect() as db:
            self.assertEqual(db.execute("SELECT refund_amount FROM orders WHERE id='FULFILL-PICKUP-1'").fetchone()[0],15000)


    def test_order_sync_does_not_create_or_duplicate_addresses_and_keeps_snapshot(self):
        code, address=self.call('POST','/api/addresses',{
            'recipient_name':'Tester','phone':'0812','address':'Alamat Awal','city':'Jakarta','is_default':True
        },self.member_token)
        self.assertEqual(code,201,address)
        aid=address['address']['id']
        before_count=len(self.call('GET','/api/addresses',token=self.member_token)[1]['addresses'])
        payload={'cart':[],'wishlist':[],'activities':[],'reviews':[],'member':{},'orders':[
            {'id':'ADDR-SNAPSHOT-1','createdAt':'2026-11-23T10:00:00','subtotal':100000,
             'total':100000,'paymentMethod':'Virtual Account BCA','gatewayRef':'GW-OK-1',
             'addressId':aid,'recipient':'Tester','phone':'0812','address':'Alamat Awal, Jakarta',
             'items':[{'productId':'E495975-000','name':'Test','price':100000,'quantity':1,'size':'M'}]},
            {'id':'ADDR-SNAPSHOT-2','createdAt':'2026-11-23T10:01:00','subtotal':100000,
             'total':100000,'paymentMethod':'Virtual Account BCA','gatewayRef':'GW-OK-2',
             'addressId':aid,'recipient':'Tester','phone':'0812','address':'Alamat Awal, Jakarta',
             'items':[{'productId':'E495975-000','name':'Test','price':100000,'quantity':1,'size':'M'}]},
            {'id':'ADDR-NO-ID-1','createdAt':'2026-11-23T10:02:00','subtotal':100000,
             'total':100000,'paymentMethod':'Virtual Account BCA','gatewayRef':'GW-OK-3',
             'recipient':'Tester','phone':'0812','address':'Alamat teks historis tanpa ID',
             'items':[{'productId':'E495975-000','name':'Test','price':100000,'quantity':1,'size':'M'}]},
        ]}
        self.assertEqual(self.call('POST','/api/member/sync',payload,self.member_token)[0],200)
        rows=self.call('GET','/api/addresses',token=self.member_token)[1]['addresses']
        self.assertEqual(len(rows),before_count)
        with server.Handler.store.connect() as db:
            self.assertEqual(db.execute("SELECT address_id FROM orders WHERE id='ADDR-SNAPSHOT-1'").fetchone()[0],aid)
            self.assertEqual(db.execute("SELECT address_id FROM orders WHERE id='ADDR-SNAPSHOT-2'").fetchone()[0],aid)
            self.assertIsNone(db.execute("SELECT address_id FROM orders WHERE id='ADDR-NO-ID-1'").fetchone()[0])
        self.assertEqual(self.call('POST',f'/api/orders/ADDR-SNAPSHOT-1/fulfillment',{
            'type':'delivery','address_id':aid,'delivery_service':'Reguler'
        },self.member_token)[0],200)
        self.assertEqual(self.call('PUT',f'/api/addresses/{aid}',{
            'recipient_name':'Tester','phone':'0812','address':'Alamat Baru','city':'Jakarta','label':'Rumah','is_default':True
        },self.member_token)[0],200)
        detail=self.call('GET','/api/orders/ADDR-SNAPSHOT-1',token=self.member_token)[1]['order']
        self.assertIn('Alamat Awal',detail['snapshot']['address'])
        self.assertEqual(len(self.call('GET','/api/addresses',token=self.member_token)[1]['addresses']),before_count)

    def test_payment_status_defaults_paid_for_confirmed_gateway_and_unpaid_for_cod(self):
        payload={'cart':[],'wishlist':[],'activities':[],'reviews':[],'member':{},'orders':[
            {'id':'PAY-ONLINE-OK','createdAt':'2026-11-23T10:00:00','subtotal':100000,'total':100000,
             'paymentMethod':'Virtual Account BCA','gatewayRef':'GW-SUCCESS',
             'items':[{'productId':'E495975-000','name':'Test','price':100000,'quantity':1,'size':'M'}]},
            {'id':'PAY-COD-1','createdAt':'2026-11-23T10:01:00','subtotal':100000,'total':100000,
             'paymentMethod':'COD (Bayar di Tempat)',
             'items':[{'productId':'E495975-000','name':'Test','price':100000,'quantity':1,'size':'M'}]},
            {'id':'PAY-INCOMPLETE','createdAt':'2026-11-23T10:02:00','subtotal':100000,'total':100000,
             'paymentMethod':'QRIS / GoPay / OVO',
             'items':[{'productId':'E495975-000','name':'Test','price':100000,'quantity':1,'size':'M'}]},
        ]}
        self.assertEqual(self.call('POST','/api/member/sync',payload,self.member_token)[0],200)
        with server.Handler.store.connect() as db:
            statuses={r['id']:r['payment_status'] for r in db.execute("SELECT id,payment_status FROM orders WHERE id LIKE 'PAY-%'")}
        self.assertEqual(statuses['PAY-ONLINE-OK'],'Paid')
        self.assertEqual(statuses['PAY-COD-1'],'Unpaid')
        self.assertEqual(statuses['PAY-INCOMPLETE'],'Pending')
        self.assertEqual(self.call('POST','/api/orders/PAY-COD-1/simulate-payment',{},self.member_token)[0],409)
        self.assertEqual(self.call('POST','/api/orders/PAY-INCOMPLETE/simulate-payment',{},self.member_token)[0],200)
        with server.Handler.store.connect() as db:
            self.assertEqual(db.execute("SELECT payment_status FROM orders WHERE id='PAY-INCOMPLETE'").fetchone()[0],'Paid')
        code, filtered=self.call('GET','/admin/api/data/orders?payment_method=COD%20%28Bayar%20di%20Tempat%29',token=self.admin_token)
        self.assertEqual(code,200)
        self.assertIn('PAY-COD-1',[x['id'] for x in filtered['items']])
        self.assertTrue(all(x['payment_method']=='COD (Bayar di Tempat)' for x in filtered['items']))


    def test_member_summary_separates_transaction_totals_from_tier_spend(self):
        payload={'cart':[],'wishlist':[],'activities':[],'reviews':[],'member':{},'orders':[
            {'id':'SUMMARY-PAID-PROCESSING','createdAt':'2026-11-23T10:00:00','subtotal':200000,
             'memberDiscount':10000,'voucherDiscount':5000,'pointsDiscount':0,
             'shippingFee':15000,'shippingDiscount':5000,'total':195000,
             'paymentMethod':'Virtual Account BCA','gatewayRef':'GW-SUMMARY',
             'items':[{'productId':'E495975-000','name':'Test','price':200000,'quantity':1,'size':'M'}]},
            {'id':'SUMMARY-COD-UNPAID','createdAt':'2026-11-23T10:01:00','subtotal':300000,
             'memberDiscount':0,'voucherDiscount':20000,'pointsDiscount':0,
             'shippingFee':15000,'shippingDiscount':0,'total':295000,
             'paymentMethod':'COD (Bayar di Tempat)',
             'items':[{'productId':'E495975-000','name':'Test','price':300000,'quantity':1,'size':'M'}]},
        ]}
        self.assertEqual(self.call('POST','/api/member/sync',payload,self.member_token)[0],200)
        summary=self.call('GET','/api/points',token=self.member_token)[1]['summary']
        self.assertEqual(summary['total_spend'],0)  # belum ada pesanan selesai
        self.assertEqual(summary['transaction_spend'],195000)
        self.assertEqual(summary['transaction_savings'],20000)

    def test_owner_cannot_delete_self(self):
        status, body = self.call('DELETE', f'/admin/api/admins/{self.admin_id}',
            {'confirm_password':'OwnerPass123!'}, self.admin_token)
        self.assertEqual(status,400)

    def test_owner_can_delete_other_owner_with_password(self):
        username='other-owner-'+str(time.time_ns())
        salt=secrets.token_hex(16)
        with server.Handler.store.connect() as db:
            cur=db.execute('INSERT INTO admins(username,name,password_hash,salt,role,created_at,active) VALUES(?,?,?,?,?,?,1)',
                (username,username,admin._hash('OtherPass123!',salt),salt,'owner',int(time.time())))
            target_id=cur.lastrowid; db.commit()
        status, body = self.call('DELETE', f'/admin/api/admins/{target_id}',
            {'confirm_password':'OwnerPass123!'}, self.admin_token)
        self.assertEqual(status,200,body)
        with server.Handler.store.connect() as db:
            self.assertIsNone(db.execute('SELECT 1 FROM admins WHERE id=?',(target_id,)).fetchone())

    def test_admin_point_adjustment_uses_append_only_ledger(self):
        status, body = self.call('POST','/admin/api/points/adjust',
            {'user_id':self.member_id,'points_delta':50,'reason':'Bonus uji'},self.admin_token)
        self.assertEqual(status,200,body)
        status, points = self.call('GET','/api/points',token=self.member_token)
        self.assertEqual(status,200)
        self.assertEqual(points['summary']['points'],250)
        status, rejected = self.call('POST','/admin/api/points/adjust',
            {'user_id':self.member_id,'points_delta':-300,'reason':'Koreksi terlalu besar'},self.admin_token)
        self.assertEqual(status,400)


if __name__ == '__main__':
    unittest.main()
